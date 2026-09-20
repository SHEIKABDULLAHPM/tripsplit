import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/calculations/money.dart';
import '../config/funding_config.dart';
import '../config/funding_legal_bundle.dart';
import '../domain/funding_exception.dart';
import '../domain/funding_info.dart';
import '../domain/razorpay_checkout.dart';
import '../providers/funding_providers.dart';

/// Checkout flow: review → accept terms → server creates the order with the
/// authoritative amount → finalize (simulated or hosted) → receipt.
class FundingCheckoutScreen extends ConsumerStatefulWidget {
  const FundingCheckoutScreen({super.key, required this.typeWire});

  final String typeWire;

  @override
  ConsumerState<FundingCheckoutScreen> createState() =>
      _FundingCheckoutScreenState();
}

class _FundingCheckoutScreenState extends ConsumerState<FundingCheckoutScreen> {
  late final FundingType _type = FundingType.fromWire(widget.typeWire);

  /// One idempotency key per review session so double-taps and retries can
  /// never create more than one order.
  late final String _idempotencyKey = _generateIdemKey();

  bool _accepted = false;
  bool _busy = false;
  bool _checkoutLaunched = false;
  FundingOrder? _order;
  RazorpayCheckoutLauncher? _launcher;

  static String _generateIdemKey() {
    const alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';
    final random = Random.secure();
    return 'flutter_${List.generate(16, (_) => alphabet[random.nextInt(alphabet.length)]).join()}';
  }

  Future<void> _createOrder() async {
    if (_busy) return;
    setState(() => _busy = true);
    fundingLog('Continue to Payment clicked for ${_type.wire}');
    try {
      // Proactive connectivity check: first verify the device has a network
      // connection, then verify the funding server is actually reachable.
      // This catches both offline and server-not-running cases early.
      final deviceOnline = await ref.read(connectivityCheckerProvider).hasConnection();
      if (!deviceOnline) {
        fundingLogError('Device has no network connection');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(fundingRequiresInternet)),
        );
        return;
      }
      fundingLog('Device has network, checking server reachability...');
      final apiClient = ref.read(fundingApiClientProvider);
      final serverReachable = await apiClient.checkConnectivity();
      if (!serverReachable) {
        fundingLogError('Funding server is not reachable');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(fundingBackendUnreachable)),
        );
        return;
      }
      fundingLog('Server is reachable, creating order...');
      final repo = ref.read(fundingRepositoryProvider);
      final order = await repo.createOrder(
        _type,
        idempotencyKey: _idempotencyKey,
      );
      fundingLog('Order created: ${order.publicReference} '
          'status=${order.status.wire} checkoutMode=${order.checkoutMode} '
          'orderId=${order.orderId} keyId=${order.keyId}');
      if (!mounted) return;
      setState(() {
        _order = order;
        _checkoutLaunched = false;
      });
      if (!order.needsSimulatedCheckout) {
        _launchHostedCheckout(order);
      }
    } on FundingException catch (e) {
      fundingLogError('Order creation failed: ${e.kind} — ${e.message}');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Opens the gateway-hosted checkout for [order]. The signature returned by
  /// its success callback is reported back to the server for verification —
  /// never trusted locally.
  void _launchHostedCheckout(FundingOrder order) {
    if (_checkoutLaunched) return;
    final keyId = order.keyId;
    final orderId = order.orderId;
    fundingLog('Launching hosted checkout: keyId=$keyId orderId=$orderId');
    final launcher = ref.read(razorpayCheckoutLauncherProvider);
    _launcher = launcher;
    launcher.clear();
    if (keyId == null || keyId.isEmpty || orderId == null || orderId.isEmpty) {
      fundingLogError('Checkout could not be started: keyId or orderId is '
          'null/empty');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Checkout could not be started. Please try again.'),
        ),
      );
      return;
    }
    setState(() => _checkoutLaunched = true);
    fundingLog('Opening Razorpay Checkout...');
    launcher.open(
      RazorpayCheckoutRequest(
        keyId: keyId,
        orderId: orderId,
        amountMinor: order.amountMinor,
        currency: order.currency,
        orderReference: order.publicReference,
      ),
      onSuccess: (paymentId, orderId, signature) =>
          unawaited(_onCheckoutSuccess(order, paymentId, orderId, signature)),
      onError: (code, message) => _onCheckoutError(order, code, message),
      onExternalWallet: _onExternalWallet,
    );
  }

  /// The gateway reported a successful payment. Report the signature to the
  /// server for verification, then hand the user to the receipt screen; the
  /// receipt always presents the server's authoritative status, so a lost
  /// connection here must never be shown as failed.
  Future<void> _onCheckoutSuccess(
    FundingOrder order,
    String paymentId,
    String orderId,
    String signature,
  ) async {
    fundingLog('Checkout success: paymentId=$paymentId orderId=$orderId');
    try {
      await ref
          .read(fundingRepositoryProvider)
          .verifyPayment(
            publicReference: order.publicReference,
            orderId: orderId,
            paymentId: paymentId,
            signature: signature,
          );
    } on Object {
      // Network loss, rejected signature, or malformed response — the receipt
      // screen re-fetches the authoritative status. Never mark VERIFIED locally.
    }
    _launcher?.clear();
    if (!mounted) return;
    context.replace(AppRoutes.fundingResult(order.publicReference));
  }

  /// The checkout was cancelled or failed. Show the reason and stay on the
  /// screen so the user can retry; no money was charged.
  void _onCheckoutError(FundingOrder order, int? code, String message) {
    fundingLogError('Checkout error: code=$code message=$message');
    _launcher?.clear();
    setState(() => _checkoutLaunched = false);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _onExternalWallet(String walletName) {
    fundingLog('External wallet selected: $walletName');
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Checkout opened in $walletName')));
  }

  @override
  void dispose() {
    _launcher?.clear();
    super.dispose();
  }

  Future<void> _finalizeSimulated(String outcome) async {
    final order = _order;
    if (order == null || _busy) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(fundingRepositoryProvider);
      final finalOrder = await repo.simulateCheckout(
        order.publicReference,
        outcome,
      );
      if (!mounted) return;
      context.replace(AppRoutes.fundingResult(finalOrder.publicReference));
    } on FundingException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkStatus() async {
    final order = _order;
    if (order == null || _busy) return;
    setState(() => _busy = true);
    try {
      final current = await ref
          .read(fundingRepositoryProvider)
          .fetchStatus(order.publicReference);
      if (!mounted) return;
      setState(() => _order = current);
      if (current.status.isVerified ||
          current.status.isFailed ||
          current.status.isCancelled ||
          current.status.isRefunded) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (!mounted) return;
        context.replace(AppRoutes.fundingResult(current.publicReference));
      }
    } on FundingException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    return Scaffold(
      appBar: AppBar(title: Text(_type.displayName)),
      body: SafeArea(
        bottom: true,
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenHorizontal,
            vertical: AppSpacing.screenVertical,
          ),
          children: [
            _amountHeader(context),
            const SizedBox(height: AppSpacing.lg),
            if (order == null)
              _ReviewSection(
                type: _type,
                accepted: _accepted,
                busy: _busy,
                onAcceptedChanged: (value) => setState(() => _accepted = value),
                onContinue: _createOrder,
                onOpenDocument: (name) =>
                    context.push(AppRoutes.fundingDocument(name)),
              )
            else
              _SandboxSection(
                order: order,
                busy: _busy,
                onOutcome: _finalizeSimulated,
                onCheckStatus: _checkStatus,
                onRetryHosted: order.needsSimulatedCheckout
                    ? null
                    : () => _launchHostedCheckout(order),
              ),
          ],
        ),
      ),
    );
  }

  Widget _amountHeader(BuildContext context) {
    final theme = Theme.of(context);
    final order = _order;
    final amount = order != null
        ? MoneyCalculator.format(order.amountMinor)
        : '₹${_type.displayRupees}';
    final caption = order != null
        ? 'Order ${order.publicReference}'
        : 'Display amount — the exact server-verified price is shown after '
              'you continue.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Amount', style: theme.textTheme.statLabel),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          amount,
          style: theme.textTheme.brandHeadline.copyWith(
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(caption, style: theme.textTheme.captionMuted),
      ],
    );
  }
}

class _ReviewSection extends StatelessWidget {
  const _ReviewSection({
    required this.type,
    required this.accepted,
    required this.busy,
    required this.onAcceptedChanged,
    required this.onContinue,
    required this.onOpenDocument,
  });

  final FundingType type;
  final bool accepted;
  final bool busy;
  final ValueChanged<bool> onAcceptedChanged;
  final VoidCallback onContinue;
  final ValueChanged<String> onOpenDocument;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final terms = FundingLegalBundle.documentFor('terms');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(type.purpose, style: theme.textTheme.bodyMuted),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Text('You are funding', style: theme.textTheme.sectionTitle),
            const Spacer(),
            Flexible(
              child: Text(
                'v${FundingConfig.currentTermsVersion}',
                textAlign: TextAlign.end,
                style: theme.textTheme.captionMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        if (terms != null)
          for (final section in terms.sections.take(2))
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(section.body, style: theme.textTheme.bodyMuted),
            ),
        TextButton(
          onPressed: () => onOpenDocument('terms'),
          child: const Text('Read the full funding terms'),
        ),
        const SizedBox(height: AppSpacing.sm),
        Card(
          margin: EdgeInsets.zero,
          child: CheckboxListTile(
            controlAffinity: ListTileControlAffinity.leading,
            value: accepted,
            onChanged: (value) => onAcceptedChanged(value ?? false),
            title: const Text('I accept the Funding Terms'),
            subtitle: Text(
              'I have read the Terms, Privacy Notice, and Refund Policy '
              '(v${FundingConfig.currentTermsVersion}).',
              style: theme.textTheme.captionMuted,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton.icon(
          onPressed: !accepted || busy ? null : onContinue,
          icon: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.arrow_forward),
          label: Text(busy ? 'Creating order…' : 'Continue to payment'),
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: Text(
            'Funding requires an internet connection. No charge happens '
            'before this point.',
            style: theme.textTheme.captionMuted,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _SandboxSection extends StatelessWidget {
  const _SandboxSection({
    required this.order,
    required this.busy,
    required this.onOutcome,
    required this.onCheckStatus,
    this.onRetryHosted,
  });

  final FundingOrder order;
  final bool busy;
  final void Function(String outcome) onOutcome;
  final VoidCallback onCheckStatus;
  final VoidCallback? onRetryHosted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!order.needsSimulatedCheckout) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              const Icon(Icons.account_balance_wallet_outlined, size: 40),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Order created — complete the hosted checkout',
                style: theme.textTheme.subtitle,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'The payment gateway will finalize this order through its '
                'secure checkout. If the checkout was interrupted, open it '
                'again below.',
                style: theme.textTheme.bodyMuted,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: busy ? null : onRetryHosted,
                icon: const Icon(Icons.lock_open_outlined),
                label: const Text('Open secure checkout'),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                onPressed: busy ? null : onCheckStatus,
                child: const Text('Check order status'),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.science_outlined, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Text('Sandbox checkout', style: theme.textTheme.subtitle),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'TripSplit is running against the sandbox funding service. '
                'No real money moves. Choose an outcome to exercise the '
                'payment pipeline.',
                style: theme.textTheme.bodyMuted,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('Complete the payment', style: theme.textTheme.sectionTitle),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          onPressed: busy ? null : () => onOutcome('success'),
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Complete payment (simulated success)'),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: busy ? null : () => onOutcome('failure'),
          icon: const Icon(Icons.error_outline),
          label: const Text('Fail payment (simulated)'),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: busy ? null : () => onOutcome('cancel'),
          icon: const Icon(Icons.close),
          label: const Text('Cancel checkout (simulated)'),
        ),
        const SizedBox(height: AppSpacing.lg),
        Center(
          child: OutlinedButton(
            onPressed: busy ? null : onCheckStatus,
            child: const Text('Check order status'),
          ),
        ),
      ],
    );
  }
}
