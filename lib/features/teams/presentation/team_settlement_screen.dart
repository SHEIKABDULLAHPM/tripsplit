import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/calculations/balances.dart';
import '../../../core/calculations/money.dart';
import '../../../core/widgets/app_section_header.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/member_avatar.dart';
import '../../../core/widgets/money_text.dart';
import '../../../core/widgets/status_chip.dart';
import '../../expenses/domain/expense.dart';
import '../../expenses/domain/expense_payment.dart';
import '../../expenses/domain/expense_share.dart';
import '../../settlements/domain/settlement.dart';
import '../../trips/data/trip_views.dart';

/// Team settlement view showing aggregated financial data for a team.
///
/// Displays:
/// - Team members
/// - Total team expenses
/// - Per-member paid amounts, shares, and net positions
/// - Final settlement transfers
class TeamSettlementScreen extends ConsumerWidget {
  const TeamSettlementScreen({
    super.key,
    required this.tripId,
    required this.teamId,
    required this.teamName,
  });

  final int tripId;
  final int teamId;
  final String teamName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final view = ref.watch(tripViewProvider(tripId));
    final teams = ref.watch(teamsForTripProvider(tripId));

    return Scaffold(
      appBar: AppBar(title: Text(teamName)),
      body: SafeArea(
        bottom: true,
        child: AsyncValueView<TripView?>(
          value: view,
          onRetry: () => ref.invalidate(tripViewProvider(tripId)),
          isEmpty: (value) => value == null,
          empty: const SizedBox.shrink(),
          builder: (tripView) {
            if (tripView == null) return const SizedBox.shrink();

            // Filter expenses for this team (an expense can span several teams)
            final teamExpenses = tripView.expenses
                .where((item) => item.expense.teamIds.contains(teamId))
                .toList();

            // Get team member IDs
            final team = teams.value?.where((t) => t.id == teamId).firstOrNull;
            if (team == null) {
              return const Center(child: Text('Team not found.'));
            }

            // Fetch actual team member IDs from the repository.
            final teamMembersAsync = ref.watch(teamMembersProvider(teamId));

            return teamMembersAsync.when(
              data: (teamMembers) {
                final teamMemberIds = teamMembers.map((m) => m.id).toSet();

                // Use the same calculation engine as the balance screen.
                // PaymentAllocator.groupOutlayByMember handles external
                // amounts correctly.
                final paymentsByExpense = PaymentAllocator.byExpense(
                  tripView.payments,
                );
                final paidByMember = <int, int>{};
                final shareByMember = <int, int>{};

                for (final item in teamExpenses) {
                  final expense = item.expense;

                  // Use PaymentAllocator for paid amounts (same engine as
                  // BalanceCalculator and SettlementCalculator).
                  final outlay = PaymentAllocator.groupOutlayByMember(
                    expense,
                    paymentsByExpense[expense.id] ?? const [],
                  );
                  for (final entry in outlay.entries) {
                    paidByMember[entry.key] =
                        (paidByMember[entry.key] ?? 0) + entry.value;
                  }

                  // Track shares (only team members' shares)
                  for (final share in item.shares) {
                    if (teamMemberIds.contains(share.memberId)) {
                      shareByMember[share.memberId] =
                          (shareByMember[share.memberId] ?? 0) +
                          share.shareMinor;
                    }
                  }
                }

                // This team's share of linked expenses. Multi-team expenses
                // are attributed through members' shares so linked-team totals
                // never double count.
                final totalTeamExpenses = shareByMember.values.fold<int>(
                  0,
                  (sum, share) => sum + share,
                );

                // Use the trip-level settlement plan (accounts for ALL
                // expenses and settlements across the entire trip). Intra-team
                // suggestions are shown first; cross-team edges that touch
                // this team (payer-balance edges) are surfaced separately so
                // the per-member "Owes n" figures always reconcile.
                final settlementPlan = tripView.settlementPlan;
                final teamSettlementSuggestions = settlementPlan.suggestions
                    .where(
                      (s) =>
                          teamMemberIds.contains(s.fromMemberId) &&
                          teamMemberIds.contains(s.toMemberId),
                    )
                    .toList();
                final crossTeamSuggestions = settlementPlan.suggestions
                    .where(
                      (s) =>
                          teamMemberIds.contains(s.fromMemberId) &&
                          !teamMemberIds.contains(s.toMemberId),
                    )
                    .toList();
                // Edges from another team's payer into this team are also
                // part of this team's settlings.
                final incomingCrossTeam = settlementPlan.suggestions
                    .where(
                      (s) =>
                          !teamMemberIds.contains(s.fromMemberId) &&
                          teamMemberIds.contains(s.toMemberId),
                    )
                    .toList();

                // Trip-level outstanding involving team members (accounts for
                // settlements already made).
                final teamRemaining =
                    teamSettlementSuggestions.fold<int>(
                      0,
                      (sum, s) => sum + s.minor,
                    ) +
                    crossTeamSuggestions.fold<int>(
                      0,
                      (sum, s) => sum + s.minor,
                    ) +
                    incomingCrossTeam.fold<int>(0, (sum, s) => sum + s.minor);

                // Payment summary for team (only cash put in by team members).
                final totalTeamPaid = paidByMember.entries
                    .where((entry) => teamMemberIds.contains(entry.key))
                    .fold<int>(0, (sum, entry) => sum + entry.value);
                final isFullyPaid = teamRemaining == 0;

                return ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.xxl,
                  ),
                  children: [
                    // Team summary card
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Team expenses',
                              style: theme.textTheme.statLabel,
                            ),
                            const SizedBox(height: 8),
                            MoneyText(
                              totalTeamExpenses,
                              style: theme.textTheme.moneyHero,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${teamExpenses.length} expense${teamExpenses.length == 1 ? '' : 's'} recorded',
                              style: theme.textTheme.captionMuted,
                            ),
                            const SizedBox(height: 12),
                            // Payment status
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: AppSpacing.sm,
                              ),
                              decoration: BoxDecoration(
                                color: isFullyPaid
                                    ? theme.colorScheme.primaryContainer
                                          .withAlpha(80)
                                    : theme.colorScheme.errorContainer
                                          .withAlpha(80),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        isFullyPaid
                                            ? Icons.check_circle_outline
                                            : Icons.pending_outlined,
                                        size: 16,
                                        color: isFullyPaid
                                            ? theme.colorScheme.primary
                                            : theme.colorScheme.error,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Remaining: ${MoneyCalculator.format(teamRemaining)}',
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                              color: isFullyPaid
                                                  ? theme.colorScheme.primary
                                                  : theme.colorScheme.error,
                                            ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Paid: ${MoneyCalculator.format(totalTeamPaid)} of ${MoneyCalculator.format(totalTeamExpenses)}',
                                    style: theme.textTheme.captionMuted,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Members: ${teamMembers.map((m) => m.name).join(', ')}',
                              style: theme.textTheme.bodyMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    // Per-expense breakdown — shows each expense and how
                    // it splits across team members.
                    if (teamExpenses.isNotEmpty) ...[
                      const SectionHeader('Expense breakdown'),
                      Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final item in teamExpenses) ...[
                                _ExpenseBreakdownRow(
                                  expense: item.expense,
                                  shares: item.shares,
                                  paymentsByExpense: paymentsByExpense,
                                  teamMemberIds: teamMemberIds,
                                  tripView: tripView,
                                ),
                                if (item != teamExpenses.last)
                                  const Divider(height: 16),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],

                    // Existing settlements between team members.
                    ..._buildExistingSettlements(
                      tripView: tripView,
                      teamMemberIds: teamMemberIds,
                      theme: theme,
                    ),

                    // Per-member breakdown
                    const SectionHeader('Per member'),
                    ..._buildMemberCards(
                      tripView: tripView,
                      paidByMember: paidByMember,
                      shareByMember: shareByMember,
                      teamMemberIds: teamMemberIds,
                      theme: theme,
                    ),

                    // Settlement transfers — trip-level outstanding involving team members,
                    // accounting for all settlements. Intra-team pairs are
                    // listed first; payer-balance edges across teams are
                    // surfaced separately so per-member figures reconcile.
                    const SectionHeader('Final settlement'),
                    if (teamRemaining == 0)
                      Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Text(
                            'No settlements needed — team is balanced.',
                            style: theme.textTheme.bodyMuted,
                          ),
                        ),
                      )
                    else ...[
                      for (final suggestion in teamSettlementSuggestions)
                        _SettlementSuggestionCard(
                          fromName: tripView
                              .memberById(suggestion.fromMemberId)
                              .name,
                          toName: tripView
                              .memberById(suggestion.toMemberId)
                              .name,
                          minor: suggestion.minor,
                          theme: theme,
                        ),
                      if (crossTeamSuggestions.isNotEmpty ||
                          incomingCrossTeam.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'With other teams',
                          style: theme.textTheme.statLabel,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        for (final suggestion in [
                          ...crossTeamSuggestions,
                          ...incomingCrossTeam,
                        ])
                          _SettlementSuggestionCard(
                            fromName: tripView
                                .memberById(suggestion.fromMemberId)
                                .name,
                            toName: tripView
                                .memberById(suggestion.toMemberId)
                                .name,
                            minor: suggestion.minor,
                            theme: theme,
                          ),
                      ],
                    ],
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildMemberCards({
    required TripView tripView,
    required Map<int, int> paidByMember,
    required Map<int, int> shareByMember,
    required Set<int> teamMemberIds,
    required ThemeData theme,
  }) {
    // Only this team's members belong in the per-member breakdown. A payer
    // from another team who fronted part of a linked multi-team expense shows
    // up in paidByMember, but must not appear as a member of THIS team.
    final memberIds = (<int>{
      ...paidByMember.keys,
      ...shareByMember.keys,
    }.intersection(teamMemberIds)).toList()..sort();

    return [
      for (final memberId in memberIds) ...[
        _TeamMemberCard(
          name: tripView.memberById(memberId).name,
          paid: paidByMember[memberId] ?? 0,
          share: shareByMember[memberId] ?? 0,
          // Settlement-aware net (same authoritative source as the Balances
          // screen and the summary card above). Recorded settlements reduce
          // what a member still owes so the per-member "Owes" status clears
          // once the team is fully paid off.
          netPosition: tripView.effectiveNetPositionOf(memberId),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    ];
  }

  List<Widget> _buildExistingSettlements({
    required TripView tripView,
    required Set<int> teamMemberIds,
    required ThemeData theme,
  }) {
    final teamSettlements = tripView.settlements
        .where(
          (s) =>
              teamMemberIds.contains(s.fromMemberId) &&
              teamMemberIds.contains(s.toMemberId) &&
              s.amountPaidMinor > 0,
        )
        .toList();
    if (teamSettlements.isEmpty) return const [];
    return [
      const SectionHeader('Settled'),
      for (final settlement in teamSettlements)
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                MemberAvatar(
                  tripView.memberById(settlement.fromMemberId).name,
                  radius: 14,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${tripView.memberById(settlement.fromMemberId).name} → '
                        '${tripView.memberById(settlement.toMemberId).name}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'Paid ${MoneyCalculator.format(settlement.amountPaidMinor)} of ${MoneyCalculator.format(settlement.amountMinor)}',
                        style: theme.textTheme.captionMuted,
                      ),
                    ],
                  ),
                ),
                StatusChip(
                  settlement.status == SettlementStatus.paid
                      ? 'Paid'
                      : 'Partial',
                  tone: settlement.status == SettlementStatus.paid
                      ? StatusTone.success
                      : StatusTone.warning,
                ),
              ],
            ),
          ),
        ),
      const SizedBox(height: AppSpacing.lg),
    ];
  }
}

class _TeamMemberCard extends StatelessWidget {
  const _TeamMemberCard({
    required this.name,
    required this.paid,
    required this.share,
    required this.netPosition,
  });

  final String name;
  final int paid;
  final int share;
  final int netPosition;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = netPosition > 0
        ? StatusTone.success
        : netPosition < 0
        ? StatusTone.warning
        : StatusTone.neutral;
    final label = netPosition > 0
        ? 'Receives'
        : netPosition < 0
        ? 'Owes'
        : 'Balanced';

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                MemberAvatar(name),
                const SizedBox(width: 12),
                Expanded(child: Text(name, style: theme.textTheme.title)),
                StatusChip(label, tone: tone),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _StatRow(label: 'Paid', minor: paid),
            _StatRow(label: 'Share', minor: share),
            _StatRow(label: 'Net', minor: netPosition.abs(), emphasize: true),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.label,
    required this.minor,
    this.emphasize = false,
  });

  final String label;
  final int minor;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMuted)),
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

/// Shows one expense's breakdown: description, group total, and per-member
/// share/paid rows for team members.
class _ExpenseBreakdownRow extends StatelessWidget {
  const _ExpenseBreakdownRow({
    required this.expense,
    required this.shares,
    required this.paymentsByExpense,
    required this.teamMemberIds,
    required this.tripView,
  });

  final Expense expense;
  final List<ExpenseShare> shares;
  final Map<int, List<ExpensePayment>> paymentsByExpense;
  final Set<int> teamMemberIds;
  final TripView tripView;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effects = PaymentAllocator.effectsPerExpense(
      expense: expense,
      shares: shares,
      paymentsByExpense: paymentsByExpense,
    );
    final teamEffects =
        effects.where((e) => teamMemberIds.contains(e.memberId)).toList()
          ..sort((a, b) => a.memberId.compareTo(b.memberId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                expense.description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            MoneyText(
              expense.amountMinor - expense.externalAmountMinor,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (final effect in teamEffects)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              children: [
                MemberAvatar(
                  tripView.memberById(effect.memberId).name,
                  radius: 8,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    tripView.memberById(effect.memberId).name,
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                MoneyText(effect.shareMinor, style: theme.textTheme.bodySmall),
                const SizedBox(width: 8),
                MoneyText(effect.paidMinor, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
      ],
    );
  }
}

/// A single suggested (or cross-team) transfer in the team settlement view.
class _SettlementSuggestionCard extends StatelessWidget {
  const _SettlementSuggestionCard({
    required this.fromName,
    required this.toName,
    required this.minor,
    required this.theme,
  });

  final String fromName;
  final String toName;
  final int minor;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            MemberAvatar(fromName, radius: 14),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$fromName → $toName',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text('To $toName', style: theme.textTheme.captionMuted),
                ],
              ),
            ),
            MoneyText(minor, style: theme.textTheme.titleBold),
          ],
        ),
      ),
    ),
  );
}
