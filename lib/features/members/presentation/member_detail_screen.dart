import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/calculations/balances.dart';
import '../../../core/calculations/money.dart';
import '../../../core/calculations/participation.dart';
import '../../../core/calculations/settlements.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/widgets/app_confirmation_dialog.dart';
import '../../../core/widgets/app_money_field.dart';
import '../../../core/widgets/app_section_header.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/member_avatar.dart';
import '../../../core/widgets/money_text.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../injection/database_providers.dart';
import '../../contributions/domain/contribution.dart';
import '../../members/domain/member.dart';
import '../../trips/data/trip_views.dart';

/// Detailed financial view for a single trip member.
///
/// Shows contribution, actual paid, expense share, net position,
/// settlement transfers, per-expense breakdown, and journey participation.
class MemberDetailScreen extends ConsumerWidget {
  const MemberDetailScreen({
    super.key,
    required this.tripId,
    required this.memberId,
  });

  final int tripId;
  final int memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final view = ref.watch(tripViewProvider(tripId));
    final journey = ref.watch(journeyViewProvider(tripId));

    return Scaffold(
      appBar: AppBar(title: const Text('Member')),
      body: SafeArea(
        bottom: true,
        child: AsyncValueView<TripView?>(
          value: view,
          onRetry: () => ref.invalidate(tripViewProvider(tripId)),
          isEmpty: (value) => value == null,
          empty: const SizedBox.shrink(),
          builder: (tripView) {
            if (tripView == null) return const SizedBox.shrink();
            final member = tripView.memberById(memberId);
            final balance = _balanceFor(tripView, memberId);
            final plan = tripView.settlementPlan;

            return ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.xxl,
              ),
              children: [
                // Header card
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            MemberAvatar(member.name),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    member.name,
                                    style: theme.textTheme.screenTitle,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Contributed ${MoneyCalculator.format(tripView.contributionTotalFor(memberId))}',
                                    style: theme.textTheme.bodyMuted,
                                  ),
                                ],
                              ),
                            ),
                            StatusChip(
                              balance?.netLabel ?? 'Balanced',
                              tone: _toneFor(balance),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _DetailStatRow(
                          label: 'Contribution',
                          minor: balance?.contribution ?? 0,
                        ),
                        _DetailStatRow(
                          label: 'Actual paid',
                          minor: balance?.actualPaid ?? 0,
                        ),
                        _DetailStatRow(
                          label: 'Expense share',
                          minor: balance?.expenseShare ?? 0,
                        ),
                        _DetailStatRow(
                          label: 'Cash remaining',
                          minor: balance?.cashRemaining ?? 0,
                        ),
                        const Divider(height: 24),
                        _DetailStatRow(
                          label: 'Net position',
                          minor: (balance?.netPosition ?? 0).abs(),
                          emphasize: true,
                          prefix: balance?.netLabel ?? 'Balanced',
                        ),
                      ],
                    ),
                  ),
                ),

                // Member contributions
                SectionHeader(
                  'Contributions',
                  trailing: IconButton(
                    tooltip: 'Record contribution',
                    onPressed: () =>
                        _showAddContribution(context, ref, memberId),
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                  ),
                ),
                _MemberContributions(
                  memberId: memberId,
                  tripView: tripView,
                  tripId: tripId,
                ),

                // Settlement transfers
                const SectionHeader('Settlement transfers'),
                _SettlementDetail(
                  memberId: memberId,
                  plan: plan,
                  tripView: tripView,
                ),

                // Per-expense breakdown
                const SectionHeader('Expenses'),
                _MemberExpenseList(memberId: memberId, tripView: tripView),

                // Journey participation
                const SectionHeader('Journey participation'),
                _JourneyParticipation(
                  memberId: memberId,
                  member: member,
                  journey: journey.value,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  MemberBalance? _balanceFor(TripView view, int memberId) {
    for (final b in view.balances.members) {
      if (b.memberId == memberId) return b;
    }
    return null;
  }

  StatusTone _toneFor(MemberBalance? balance) {
    if (balance == null) return StatusTone.neutral;
    if (balance.netPosition > 0) return StatusTone.success;
    if (balance.netPosition < 0) return StatusTone.warning;
    return StatusTone.neutral;
  }

  Future<void> _showAddContribution(
    BuildContext context,
    WidgetRef ref,
    int memberId,
  ) async {
    final controller = TextEditingController();
    final noteController = TextEditingController();
    final result = await showDialog<(int, String?)>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record contribution'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppMoneyField(
              controller: controller,
              label: 'Amount',
              constraint: AppMoneyConstraint.requiredPositive,
              autofocus: true,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: noteController,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final amount = MoneyCalculator.parseToMinorOrNull(
                controller.text,
              );
              if (amount != null && amount > 0) {
                Navigator.pop(ctx, (amount, noteController.text.trim()));
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && context.mounted) {
      try {
        await ref
            .read(contributionRepositoryProvider)
            .save(
              Contribution(
                id: 0,
                tripId: tripId,
                memberId: memberId,
                amountMinor: result.$1,
                note: (result.$2?.isEmpty ?? true) ? null : result.$2,
                createdAt: DateTime.now(),
              ),
            );
      } on AppException catch (error) {
        if (context.mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}

class _DetailStatRow extends StatelessWidget {
  const _DetailStatRow({
    required this.label,
    required this.minor,
    this.emphasize = false,
    this.prefix,
  });

  final String label;
  final int minor;
  final bool emphasize;
  final String? prefix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMuted)),
          if (prefix != null) ...[
            Text('$prefix ', style: theme.textTheme.captionMuted),
          ],
          MoneyText(
            minor,
            style: emphasize
                ? theme.textTheme.statValue
                : theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _SettlementDetail extends StatelessWidget {
  const _SettlementDetail({
    required this.memberId,
    required this.plan,
    required this.tripView,
  });

  final int memberId;
  final SettlementResult plan;
  final TripView tripView;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final receives = <_Transfer>[];
    final pays = <_Transfer>[];

    for (final s in plan.suggestions) {
      if (s.toMemberId == memberId && s.minor > 0) {
        receives.add(
          _Transfer(
            name: tripView.memberById(s.fromMemberId).name,
            minor: s.minor,
          ),
        );
      }
      if (s.fromMemberId == memberId && s.minor > 0) {
        pays.add(
          _Transfer(
            name: tripView.memberById(s.toMemberId).name,
            minor: s.minor,
          ),
        );
      }
    }

    if (receives.isEmpty && pays.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            'No outstanding transfers.',
            style: theme.textTheme.bodyMuted,
          ),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (pays.isNotEmpty) ...[
              Text('Pays:', style: theme.textTheme.captionMuted),
              for (final t in pays)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.arrow_forward, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(t.name, style: theme.textTheme.bodyMedium),
                      ),
                      MoneyText(t.minor, style: theme.textTheme.statValue),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
            ],
            if (receives.isNotEmpty) ...[
              Text('Receives from:', style: theme.textTheme.captionMuted),
              for (final t in receives)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.arrow_back, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(t.name, style: theme.textTheme.bodyMedium),
                      ),
                      MoneyText(t.minor, style: theme.textTheme.statValue),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Transfer {
  const _Transfer({required this.name, required this.minor});
  final String name;
  final int minor;
}

class _MemberExpenseList extends StatelessWidget {
  const _MemberExpenseList({required this.memberId, required this.tripView});

  final int memberId;
  final TripView tripView;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effects = <MemberExpenseEffect>[];
    final paymentsByExpense = PaymentAllocator.byExpense(tripView.payments);
    for (final item in tripView.expenses) {
      effects.addAll(
        PaymentAllocator.effectsPerExpense(
          expense: item.expense,
          shares: item.shares,
          paymentsByExpense: paymentsByExpense,
        ),
      );
    }
    final mine = effects.where((e) => e.memberId == memberId).toList()
      ..sort((a, b) => a.expenseId.compareTo(b.expenseId));

    if (mine.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text('No expenses yet.', style: theme.textTheme.bodyMuted),
        ),
      );
    }

    String expenseName(int expenseId) {
      for (final item in tripView.expenses) {
        if (item.expense.id == expenseId) {
          return item.expense.description;
        }
      }
      return 'Expense #$expenseId';
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          for (final effect in mine)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 2,
              ),
              leading: MemberAvatar(expenseName(effect.expenseId), radius: 11),
              title: Text(
                expenseName(effect.expenseId),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                effect.netMinor == 0
                    ? 'Paid their share'
                    : effect.netMinor > 0
                    ? 'Paid ${MoneyCalculator.format(effect.netMinor)} more'
                    : 'Owes ${MoneyCalculator.format(-effect.netMinor)}',
                style: theme.textTheme.captionMuted,
              ),
              trailing: MoneyText(
                effect.paidMinor,
                style: theme.textTheme.bodyMedium,
              ),
            ),
        ],
      ),
    );
  }
}

class _JourneyParticipation extends StatelessWidget {
  const _JourneyParticipation({
    required this.memberId,
    required this.member,
    required this.journey,
  });

  final int memberId;
  final Member member;
  final JourneyView? journey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (journey == null || journey!.segments.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            'No journey defined yet.',
            style: theme.textTheme.bodyMuted,
          ),
        ),
      );
    }

    final segments = journey!.segments;
    final locations = journey!.locations;
    final participations = journey!.participations;

    String locationName(int id) {
      for (final l in locations) {
        if (l.id == id) return l.name;
      }
      return '?';
    }

    // Use ParticipationCalculator for correct participation logic,
    // including complex journeys with duplicate locations.
    final allMembers = [member];

    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < segments.length; i++) ...[
            Builder(
              builder: (context) {
                final seg = segments[i];
                final startName = locationName(seg.startLocationId);
                final endName = locationName(seg.endLocationId);
                final participating =
                    ParticipationCalculator.participatesInSegment(
                      memberId: memberId,
                      segment: seg,
                      segmentOrder: i,
                      members: allMembers,
                      segments: segments,
                      locations: locations,
                      participations: participations,
                    );
                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 2,
                  ),
                  leading: Icon(
                    participating
                        ? Icons.check_circle_outline
                        : Icons.cancel_outlined,
                    size: 18,
                    color: participating
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withAlpha(128),
                  ),
                  title: Text(
                    '$startName → $endName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      decoration: participating
                          ? null
                          : TextDecoration.lineThrough,
                      color: participating
                          ? null
                          : theme.colorScheme.onSurface.withAlpha(128),
                    ),
                  ),
                  trailing: Text(
                    participating ? 'Participating' : 'Not participating',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.captionMuted,
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _MemberContributions extends ConsumerWidget {
  const _MemberContributions({
    required this.memberId,
    required this.tripView,
    required this.tripId,
  });

  final int memberId;
  final TripView tripView;
  final int tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final contributions =
        tripView.contributions.where((c) => c.memberId == memberId).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (contributions.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            'No contributions yet.',
            style: theme.textTheme.bodyMuted,
          ),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          for (final c in contributions)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xxs,
              ),
              title: MoneyText(c.amountMinor, style: theme.textTheme.statValue),
              subtitle: c.note != null
                  ? Text(
                      c.note!,
                      style: theme.textTheme.captionMuted,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : null,
              trailing: PopupMenuButton<String>(
                tooltip: 'Actions',
                onSelected: (action) => _handleAction(context, ref, action, c),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    WidgetRef ref,
    String action,
    Contribution contribution,
  ) async {
    if (action == 'edit') {
      final controller = TextEditingController(
        text: MoneyCalculator.formatNoSymbol(contribution.amountMinor),
      );
      final noteController = TextEditingController(
        text: contribution.note ?? '',
      );
      final result = await showDialog<(int, String?)>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Edit contribution'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppMoneyField(
                controller: controller,
                label: 'Amount',
                constraint: AppMoneyConstraint.requiredPositive,
                autofocus: true,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: noteController,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final amount = MoneyCalculator.parseToMinorOrNull(
                  controller.text,
                );
                if (amount != null && amount > 0) {
                  Navigator.pop(ctx, (amount, noteController.text.trim()));
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (result != null && context.mounted) {
        try {
          await ref
              .read(contributionRepositoryProvider)
              .save(
                contribution.copyWith(
                  amountMinor: result.$1,
                  note: (result.$2?.isEmpty ?? true) ? null : result.$2,
                ),
              );
        } on AppException catch (error) {
          if (context.mounted)
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(error.message)));
        }
      }
    } else if (action == 'delete') {
      final confirmed = await showAppConfirmation(
        context,
        title: 'Delete contribution?',
        message:
            'This removes the ${MoneyCalculator.format(contribution.amountMinor)} contribution.',
        confirmLabel: 'Delete',
      );
      if (confirmed && context.mounted) {
        try {
          await ref
              .read(contributionRepositoryProvider)
              .deleteById(contribution.id);
        } on AppException catch (error) {
          if (context.mounted)
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(error.message)));
        }
      }
    }
  }
}
