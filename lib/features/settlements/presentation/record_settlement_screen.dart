import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_financial_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/calculations/money.dart';
import '../../../core/calculations/settlements.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/widgets/app_money_field.dart';
import '../../../core/widgets/app_section_header.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/money_text.dart';
import '../../../injection/database_providers.dart';
import '../../trips/data/trip_views.dart';

/// Record-payment screen shown at `/trip/:tripId/settlements/new`.
///
/// A settlement is a transfer (not an expense): recording it clears debt
/// without touching reported spending or budget usage.
class RecordSettlementScreen extends ConsumerStatefulWidget {
  const RecordSettlementScreen({super.key, required this.tripId});

  final int tripId;

  @override
  ConsumerState<RecordSettlementScreen> createState() =>
      _RecordSettlementScreenState();
}

/// Selection carried into the record-payment screen via GoRouter [extra].
class RecordSettlementSelection {
  const RecordSettlementSelection({
    required this.fromMemberId,
    required this.toMemberId,
    this.amountMinor,
  });

  final int fromMemberId;
  final int toMemberId;

  /// Suggestion amount to pre-fill into the payment field (optional).
  final int? amountMinor;
}

class _RecordSettlementScreenState
    extends ConsumerState<RecordSettlementScreen> {
  final _formKey = GlobalKey<FormState>();
  final _noteController = TextEditingController();
  int? _fromMemberId;
  int? _toMemberId;
  final _paidController = TextEditingController();
  bool _saving = false;
  bool _selectionApplied = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_selectionApplied) return;
    _selectionApplied = true;
    // GoRouter passes `extra` via GoRouterState; fall back to ModalRoute
    // arguments for tests that push directly.
    final extra =
        GoRouterState.of(context).extra ??
        ModalRoute.of(context)?.settings.arguments;
    if (extra is RecordSettlementSelection) {
      _fromMemberId = extra.fromMemberId;
      _toMemberId = extra.toMemberId;
      if (extra.amountMinor != null) {
        _paidController.text = MoneyCalculator.formatNoSymbol(
          extra.amountMinor!,
        );
      }
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    _paidController.dispose();
    super.dispose();
  }

  int get _outstanding {
    final view = ref.read(tripViewProvider(widget.tripId)).value;
    if (view == null || _fromMemberId == null || _toMemberId == null) {
      return 0;
    }
    return SettlementCalculator.outstandingBetween(
      view.settlementPlan.suggestions,
      fromMemberId: _fromMemberId!,
      toMemberId: _toMemberId!,
    );
  }

  int get _paidMinor =>
      MoneyCalculator.parseToMinorOrNull(_paidController.text) ?? 0;

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final paidMinor = MoneyCalculator.parseToMinor(
      _paidController.text,
      label: 'Amount paid',
    );
    setState(() => _saving = true);
    try {
      await ref
          .read(settlementRepositoryProvider)
          .recordPayment(
            tripId: widget.tripId,
            fromMemberId: _fromMemberId!,
            toMemberId: _toMemberId!,
            amountMinor: _outstanding,
            paidMinor: paidMinor,
            note: _noteController.text.trim().isEmpty
                ? null
                : _noteController.text.trim(),
          );
      if (mounted) {
        context.pop();
      }
    } on AppException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final view = ref.watch(tripViewProvider(widget.tripId));
    final outstanding = _outstanding;
    final paid = _paidMinor;
    final remaining = outstanding - paid;

    return Scaffold(
      appBar: AppBar(title: const Text('Record payment')),
      body: SafeArea(
        bottom: true,
        child: AsyncValueView<TripView?>(
          value: view,
          onRetry: () => ref.invalidate(tripViewProvider(widget.tripId)),
          isEmpty: (value) => value == null || value.members.isEmpty,
          empty: const Center(child: Text('Nothing to settle yet.')),
          builder: (tripView) {
            if (tripView == null) {
              return const Center(child: Text('Nothing to settle yet.'));
            }
            return Form(
              key: _formKey,
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.lg,
                  AppSpacing.xl,
                  AppSpacing.xxl,
                ),
                children: [
                  Text(
                    'A settlement is a transfer, not an expense. Recording a '
                    'payment clears debt without changing reported spending or '
                    'budget usage.',
                    style: theme.textTheme.bodyMuted,
                  ),
                  const SectionHeader('Transfer'),
                  DropdownButtonFormField<int>(
                    initialValue: _fromMemberId,
                    decoration: const InputDecoration(labelText: 'Who pays'),
                    items: [
                      for (final member in tripView.members)
                        DropdownMenuItem(
                          value: member.id,
                          child: Text(member.name),
                        ),
                    ],
                    onChanged: (value) => setState(() => _fromMemberId = value),
                    validator: (value) =>
                        value == null ? 'Select who pays' : null,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  DropdownButtonFormField<int>(
                    initialValue: _toMemberId,
                    decoration: const InputDecoration(
                      labelText: 'Who receives',
                    ),
                    items: [
                      for (final member in tripView.members)
                        if (member.id != _fromMemberId)
                          DropdownMenuItem(
                            value: member.id,
                            child: Text(member.name),
                          ),
                    ],
                    onChanged: (value) => setState(() => _toMemberId = value),
                    validator: (value) =>
                        value == null ? 'Select who receives' : null,
                  ),
                  if (outstanding > 0) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _ObligationCard(
                      outstandingMinor: outstanding,
                      paidMinor: paid,
                      remainingMinor: remaining,
                    ),
                  ],
                  const SectionHeader('Payment'),
                  AppMoneyField(
                    controller: _paidController,
                    label: 'Amount paid',
                    hintText: 'e.g. 365.40',
                    constraint: AppMoneyConstraint.requiredPositive,
                    maxMinor: outstanding > 0 ? outstanding : null,
                    maxStrict: false,
                    maxExceededMessage:
                        'Cannot pay more than the outstanding amount.',
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextFormField(
                    controller: _noteController,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Note (optional)',
                      hintText: 'Optional',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton.icon(
                    onPressed:
                        _saving || _fromMemberId == null || _toMemberId == null
                        ? null
                        : _submit,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: const Text('Record payment'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ObligationCard extends StatelessWidget {
  const _ObligationCard({
    required this.outstandingMinor,
    required this.paidMinor,
    required this.remainingMinor,
  });

  final int outstandingMinor;
  final int paidMinor;
  final int remainingMinor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Outstanding', style: theme.textTheme.statLabel),
            const SizedBox(height: 4),
            MoneyText(outstandingMinor, style: theme.textTheme.moneyStrong),
            const Divider(height: 24),
            if (paidMinor > 0)
              _BreakdownRow(
                label: 'This payment',
                minor: paidMinor,
                style: theme.textTheme.bodyMedium,
              ),
            _BreakdownRow(
              label: paidMinor > 0 ? 'Remaining after' : 'Remaining',
              minor: remainingMinor.clamp(0, outstandingMinor),
              style: theme.textTheme.statValue,
              accent: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.label,
    required this.minor,
    required this.style,
    this.accent = false,
  });

  final String label;
  final int minor;
  final TextStyle? style;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final financial = context.financial;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMuted),
          ),
          MoneyText(
            minor,
            style: accent ? style?.copyWith(color: financial.owes) : style,
          ),
        ],
      ),
    );
  }
}
