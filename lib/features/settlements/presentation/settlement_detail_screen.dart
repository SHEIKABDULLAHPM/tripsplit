import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_financial_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/calculations/money.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/widgets/app_confirmation_dialog.dart';
import '../../../core/widgets/app_money_field.dart';
import '../../../core/widgets/app_section_header.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/member_avatar.dart';
import '../../../core/widgets/money_text.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../injection/database_providers.dart';
import '../../settlements/domain/settlement.dart';
import '../../trips/data/trip_views.dart';
import 'record_settlement_screen.dart' show RecordSettlementSelection;

/// Detail screen for a single settlement, shown at
/// `/trip/:tripId/settlements/:settlementId`.
///
/// Displays the transfer direction, financial breakdown, status, payment
/// history for the pair, and an action to record further payments.
class SettlementDetailScreen extends ConsumerWidget {
  const SettlementDetailScreen({
    super.key,
    required this.tripId,
    required this.settlementId,
  });

  final int tripId;
  final int settlementId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(tripViewProvider(tripId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settlement'),
        actions: [
          IconButton(
            tooltip: 'Edit payment',
            onPressed: () => _editPaid(context, ref),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Delete settlement',
            onPressed: () => _confirmDelete(context, ref),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SafeArea(
        bottom: true,
        child: AsyncValueView<TripView?>(
          value: view,
          onRetry: () => ref.invalidate(tripViewProvider(tripId)),
          isEmpty: (value) => value == null,
          empty: const Center(child: Text('Settlement not found.')),
          builder: (tripView) {
            if (tripView == null) {
              return const Center(child: Text('Settlement not found.'));
            }
            final settlement = tripView.settlements
                .cast<Settlement?>()
                .firstWhere(
                  (s) => s != null && s.id == settlementId,
                  orElse: () => null,
                );
            if (settlement == null) {
              return const Center(child: Text('Settlement not found.'));
            }
            return _SettlementBody(
              tripId: tripId,
              settlement: settlement,
              tripView: tripView,
            );
          },
        ),
      ),
    );
  }

  Future<void> _editPaid(BuildContext context, WidgetRef ref) async {
    final view = ref.read(tripViewProvider(tripId)).value;
    if (view == null) return;
    final settlement = view.settlements.cast<Settlement?>().firstWhere(
      (s) => s != null && s.id == settlementId,
      orElse: () => null,
    );
    if (settlement == null) return;

    final paidMinor = await showDialog<int>(
      context: context,
      builder: (_) => _EditPaidDialog(
        initialPaidMinor: settlement.amountPaidMinor,
        obligationMinor: view.settlementObligationBetween(
          settlement.fromMemberId,
          settlement.toMemberId,
        ),
        outstandingMinor: view.settlementRemainingBetween(
          settlement.fromMemberId,
          settlement.toMemberId,
        ),
      ),
    );
    if (paidMinor == null || !context.mounted) return;
    try {
      await ref
          .read(settlementRepositoryProvider)
          .setPaidAmount(settlementId: settlementId, paidMinor: paidMinor);
    } on AppException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showAppConfirmation(
      context,
      title: 'Delete settlement?',
      message:
          'This removes the recorded payment and restores the outstanding debt.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ref.read(settlementRepositoryProvider).deleteById(settlementId);
      if (context.mounted) context.pop();
    } on AppException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

class _SettlementBody extends ConsumerWidget {
  const _SettlementBody({
    required this.tripId,
    required this.settlement,
    required this.tripView,
  });

  final int tripId;
  final Settlement settlement;
  final TripView tripView;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final financial = context.financial;
    final fromMember = tripView.memberById(settlement.fromMemberId);
    final toMember = tripView.memberById(settlement.toMemberId);

    // Live figures derived from the current plan (single source of truth) so
    // the detail screen can never drift from the outstanding hero or the
    // suggested transfers when expenses change after this transfer was
    // recorded.
    final outstanding = tripView.settlementObligationBetween(
      settlement.fromMemberId,
      settlement.toMemberId,
    );
    final paid = tripView.settlementPaidBetween(
      settlement.fromMemberId,
      settlement.toMemberId,
    );
    final remaining = tripView.settlementRemainingBetween(
      settlement.fromMemberId,
      settlement.toMemberId,
    );

    final status = switch ((remaining <= 0, paid > 0)) {
      (true, _) => SettlementStatus.paid,
      (false, true) => SettlementStatus.partial,
      (false, false) => SettlementStatus.outstanding,
    };
    final tone = switch (status) {
      SettlementStatus.paid => StatusTone.success,
      SettlementStatus.partial => StatusTone.warning,
      SettlementStatus.outstanding => StatusTone.neutral,
    };
    final statusLabel = switch (status) {
      SettlementStatus.paid => 'Paid',
      SettlementStatus.partial => 'Partial',
      SettlementStatus.outstanding => 'Outstanding',
    };

    final pairHistory =
        tripView.settlements
            .where(
              (s) =>
                  s.id != settlement.id &&
                  s.fromMemberId == settlement.fromMemberId &&
                  s.toMemberId == settlement.toMemberId,
            )
            .toList()
          ..sort((a, b) => b.settledAt.compareTo(a.settledAt));

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xxxl,
      ),
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                Row(
                  children: [
                    MemberAvatar(fromMember.name, radius: 24),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fromMember.name,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text('Pays', style: theme.textTheme.captionMuted),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward, color: financial.owes, size: 20),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            toMember.name,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text('Receives', style: theme.textTheme.captionMuted),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    MemberAvatar(toMember.name, radius: 24),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                StatusChip(statusLabel, tone: tone),
              ],
            ),
          ),
        ),
        const SectionHeader('Financials'),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                _BreakdownRow(
                  label: 'Amount obligated',
                  minor: outstanding,
                  style: theme.textTheme.statValue,
                ),
                const SizedBox(height: AppSpacing.sm),
                _BreakdownRow(
                  label: 'Amount paid',
                  minor: paid,
                  style: theme.textTheme.statValue,
                  accentColor: paid > 0 ? financial.receives : null,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Divider(),
                ),
                _BreakdownRow(
                  label: 'Remaining',
                  minor: remaining,
                  style: theme.textTheme.moneyStrong,
                  accentColor: financial.owes,
                ),
              ],
            ),
          ),
        ),
        if (settlement.note != null && settlement.note!.isNotEmpty) ...[
          const SectionHeader('Note'),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(settlement.note!, style: theme.textTheme.bodyMedium),
            ),
          ),
        ],
        if (pairHistory.isNotEmpty) ...[
          const SectionHeader('Payment history'),
          for (final past in pairHistory)
            Card(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _HistoryEntry(settlement: past, tripView: tripView),
            ),
        ],
        if (remaining > 0) ...[
          const SizedBox(height: AppSpacing.xl),
          FilledButton.icon(
            onPressed: () => context.push(
              AppRoutes.recordSettlement(tripId),
              extra: RecordSettlementSelection(
                fromMemberId: settlement.fromMemberId,
                toMemberId: settlement.toMemberId,
              ),
            ),
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Record payment'),
          ),
        ],
        if (paid > 0) ...[
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: () => _markUnpaid(context, ref),
            icon: const Icon(Icons.undo),
            label: const Text('Mark as unpaid'),
          ),
        ],
      ],
    );
  }

  Future<void> _markUnpaid(BuildContext context, WidgetRef ref) async {
    final confirmed = await showAppConfirmation(
      context,
      title: 'Mark settlement as unpaid?',
      message:
          'This resets the paid amount to ₹0 for this settlement. You can '
          'record the payment again later.',
      confirmLabel: 'Mark unpaid',
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ref
          .read(settlementRepositoryProvider)
          .setPaidAmount(settlementId: settlement.id, paidMinor: 0);
    } on AppException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.label,
    required this.minor,
    required this.style,
    this.accentColor,
  });

  final String label;
  final int minor;
  final TextStyle? style;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
    child: Row(
      children: [
        Flexible(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMuted,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        MoneyText(
          minor,
          style: accentColor != null
              ? style?.copyWith(color: accentColor)
              : style,
        ),
      ],
    ),
  );
}

class _HistoryEntry extends StatelessWidget {
  const _HistoryEntry({required this.settlement, required this.tripView});

  final Settlement settlement;
  final TripView tripView;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = settlement.status;
    final tone = switch (status) {
      SettlementStatus.paid => StatusTone.success,
      SettlementStatus.partial => StatusTone.warning,
      SettlementStatus.outstanding => StatusTone.neutral,
    };
    final label = switch (status) {
      SettlementStatus.paid => 'Paid',
      SettlementStatus.partial => 'Partial',
      SettlementStatus.outstanding => 'Outstanding',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          MemberAvatar(
            tripView.memberById(settlement.fromMemberId).name,
            radius: 14,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  MoneyCalculator.format(settlement.amountPaidMinor),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (settlement.note != null && settlement.note!.isNotEmpty)
                  Text(
                    settlement.note!,
                    style: theme.textTheme.captionMuted,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          StatusChip(label, tone: tone),
        ],
      ),
    );
  }
}

class _EditPaidDialog extends StatefulWidget {
  const _EditPaidDialog({
    required this.initialPaidMinor,
    required this.obligationMinor,
    required this.outstandingMinor,
  });

  final int initialPaidMinor;
  final int obligationMinor;

  /// What is still owed for this pair right now per the live plan.
  final int outstandingMinor;

  @override
  State<_EditPaidDialog> createState() => _EditPaidDialogState();
}

class _EditPaidDialogState extends State<_EditPaidDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _paidController;

  @override
  void initState() {
    super.initState();
    _paidController = TextEditingController(
      text: MoneyCalculator.formatNoSymbol(widget.initialPaidMinor),
    );
  }

  @override
  void dispose() {
    _paidController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(
      context,
    ).pop(MoneyCalculator.parseToMinorOrNull(_paidController.text) ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentPaid =
        MoneyCalculator.parseToMinorOrNull(_paidController.text) ?? 0;
    return AlertDialog(
      title: const Text('Edit payment'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.outstandingMinor > 0
                  ? 'This pair still owes '
                        '${MoneyCalculator.format(widget.outstandingMinor)}. '
                        'The current obligation is '
                        '${MoneyCalculator.format(widget.obligationMinor)}.'
                  : 'Adjust how much has been paid. The obligation is '
                        '${MoneyCalculator.format(widget.obligationMinor)}.',
              style: theme.textTheme.bodyMuted,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppMoneyField(
              controller: _paidController,
              label: 'Amount paid',
              hintText: 'e.g. 500',
              constraint: AppMoneyConstraint.optional,
              maxMinor: widget.obligationMinor,
              maxExceededMessage: 'Cannot exceed the obligated amount.',
              onChanged: (_) => setState(() {}),
            ),
            if (currentPaid > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    _paidController.text = '0';
                    setState(() {});
                  },
                  icon: const Icon(Icons.undo, size: 18),
                  label: const Text('Mark as unpaid'),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
