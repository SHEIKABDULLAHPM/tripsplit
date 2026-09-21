import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/calculations/balances.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/member_avatar.dart';
import '../../../core/widgets/money_text.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../injection/database_providers.dart';
import '../../journey/domain/journey.dart';
import '../../members/domain/member.dart';
import '../../trips/data/trip_views.dart';

/// Team management: create teams, manage membership, view team expenses.
class TeamsScreen extends ConsumerWidget {
  const TeamsScreen({super.key, required this.tripId});

  final int tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(tripViewProvider(tripId));
    final teams = ref.watch(teamsForTripProvider(tripId));

    return Scaffold(
      appBar: AppBar(title: const Text('Teams')),
      body: SafeArea(
        bottom: true,
        child: AsyncValueView<TripView?>(
          value: view,
          onRetry: () => ref.invalidate(tripViewProvider(tripId)),
          isEmpty: (value) => value == null,
          empty: const EmptyState(
            icon: Icons.groups_outlined,
            title: 'No trip',
            message: 'This trip could not be found.',
          ),
          builder: (tripView) {
            if (tripView == null) return const SizedBox.shrink();
            return _TeamsBody(
              tripId: tripId,
              members: tripView.members,
              teams: teams.value ?? const <Team>[],
              tripView: tripView,
            );
          },
        ),
      ),
    );
  }
}

class _TeamsBody extends ConsumerStatefulWidget {
  const _TeamsBody({
    required this.tripId,
    required this.members,
    required this.teams,
    required this.tripView,
  });

  final int tripId;
  final List<Member> members;
  final List<Team> teams;
  final TripView tripView;

  @override
  ConsumerState<_TeamsBody> createState() => _TeamsBodyState();
}

class _TeamsBodyState extends ConsumerState<_TeamsBody> {
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _createTeam() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    try {
      await ref.read(teamRepositoryProvider).createTeam(widget.tripId, name);
      _nameController.clear();
      if (mounted) Navigator.of(context).pop();
    } on AppException catch (e) {
      _showSnack(e.message);
    }
  }

  void _showCreateDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New team'),
        content: TextField(
          controller: _nameController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Team name',
            hintText: 'e.g. Car 1',
          ),
          textCapitalization: TextCapitalization.words,
          onSubmitted: (_) => _createTeam(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: _createTeam, child: const Text('Create')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      children: [
        if (widget.teams.isEmpty)
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Teams group members so expenses can be shared within a sub-group — e.g. the people riding one car.',
                    style: theme.textTheme.bodyMuted,
                  ),
                  const SizedBox(height: 12),
                  Icon(
                    Icons.groups_outlined,
                    size: 48,
                    color: theme.colorScheme.primary.withAlpha(80),
                  ),
                ],
              ),
            ),
          )
        else
          for (final team in widget.teams)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _TeamCard(
                tripId: widget.tripId,
                team: team,
                members: widget.members,
                tripView: widget.tripView,
                onError: _showSnack,
              ),
            ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _showCreateDialog,
            icon: const Icon(Icons.add),
            label: const Text('Create team'),
          ),
        ),
      ],
    );
  }
}

class _TeamCard extends ConsumerStatefulWidget {
  const _TeamCard({
    required this.tripId,
    required this.team,
    required this.members,
    required this.tripView,
    required this.onError,
  });

  final int tripId;
  final Team team;
  final List<Member> members;
  final TripView tripView;
  final void Function(String message) onError;

  @override
  ConsumerState<_TeamCard> createState() => _TeamCardState();
}

class _TeamCardState extends ConsumerState<_TeamCard> {
  Future<void> _editMembers() async {
    final teamMembersData = ref.read(teamMembersProvider(widget.team.id));
    final currentMembers = teamMembersData.value ?? const <Member>[];
    final selected = currentMembers.map((m) => m.id).toSet();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.team.name} members',
                  style: Theme.of(sheetContext).textTheme.sectionTitle,
                ),
                const SizedBox(height: 4),
                Text(
                  'Select which trip members belong to this team.',
                  style: Theme.of(sheetContext).textTheme.captionMuted,
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final member in widget.members)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(member.name),
                          value: selected.contains(member.id),
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (checked) async {
                            try {
                              final repo = ref.read(teamRepositoryProvider);
                              if (checked == true) {
                                await repo.addMember(
                                  teamId: widget.team.id,
                                  memberId: member.id,
                                );
                                setSheetState(() => selected.add(member.id));
                              } else {
                                await repo.removeMember(
                                  teamId: widget.team.id,
                                  memberId: member.id,
                                );
                                setSheetState(() => selected.remove(member.id));
                              }
                            } on AppException catch (e) {
                              if (mounted) widget.onError(e.message);
                            }
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _renameTeam() async {
    final controller = TextEditingController(text: widget.team.name);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename team'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.trim().isEmpty) return;
    try {
      await ref.read(teamRepositoryProvider).renameTeam(widget.team.id, result);
    } on AppException catch (e) {
      if (mounted) widget.onError(e.message);
    }
  }

  Future<void> _deleteTeam() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete team?'),
        content: Text(
          'Delete "${widget.team.name}"? This will remove all team memberships but keep expenses.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(teamRepositoryProvider).deleteTeam(widget.team.id);
    } on AppException catch (e) {
      if (mounted) widget.onError(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final teamMembers = ref.watch(teamMembersProvider(widget.team.id));

    // Count team expenses
    final teamExpenses = widget.tripView.expenses
        .where((e) => e.expense.teamIds.contains(widget.team.id))
        .toList();

    // Compute team-level financials using the same calculation engine
    final paymentsByExpense = PaymentAllocator.byExpense(
      widget.tripView.payments,
    );
    final teamMemberIds = teamMembers.value?.map((m) => m.id).toSet() ?? {};

    final paidByMember = <int, int>{};
    final shareByMember = <int, int>{};

    for (final item in teamExpenses) {
      final expense = item.expense;
      // Paid amounts via PaymentAllocator (same engine as balance screen).
      // Only cash paid by this team's own members is attributed here, so a
      // multi-team expense never shows another team's payer on this card.
      final outlay = PaymentAllocator.groupOutlayByMember(
        expense,
        paymentsByExpense[expense.id] ?? const [],
      );
      for (final entry in outlay.entries) {
        if (!teamMemberIds.contains(entry.key)) continue;
        paidByMember[entry.key] = (paidByMember[entry.key] ?? 0) + entry.value;
      }

      // Share amounts (only for team members)
      for (final share in item.shares) {
        if (teamMemberIds.contains(share.memberId)) {
          shareByMember[share.memberId] =
              (shareByMember[share.memberId] ?? 0) + share.shareMinor;
        }
      }
    }

    // A multi-team expense is attributed to this team through its members'
    // shares, and only what team members actually paid counts, so the per-team
    // totals never double count or include another team's cash.
    final totalTeamExpense = shareByMember.values.fold<int>(
      0,
      (sum, share) => sum + share,
    );
    final totalTeamPaid = paidByMember.entries
        .where((entry) => teamMemberIds.contains(entry.key))
        .fold<int>(0, (sum, entry) => sum + entry.value);
    final teamRemaining = totalTeamExpense - totalTeamPaid;

    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: Text(
              widget.team.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              '${teamExpenses.length} expense${teamExpenses.length == 1 ? '' : 's'}',
              style: theme.textTheme.captionMuted,
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (action) {
                switch (action) {
                  case 'members':
                    _editMembers();
                  case 'settlement':
                    context.push(
                      AppRoutes.teamSettlement(
                        widget.tripId,
                        widget.team.id,
                        name: widget.team.name,
                      ),
                    );
                  case 'expense':
                    context.push(
                      AppRoutes.addExpense(
                        widget.tripId,
                        teamId: widget.team.id,
                      ),
                    );
                  case 'rename':
                    _renameTeam();
                  case 'delete':
                    _deleteTeam();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'members',
                  child: Text('Manage members'),
                ),
                const PopupMenuItem(
                  value: 'expense',
                  child: Text('Add team expense'),
                ),
                const PopupMenuItem(
                  value: 'settlement',
                  child: Text('Settlement view'),
                ),
                const PopupMenuItem(value: 'rename', child: Text('Rename')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ),
          // Team expense summary (only when expenses exist)
          if (teamExpenses.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _TeamStatBox(
                          label: 'Expense',
                          minor: totalTeamExpense,
                        ),
                      ),
                      Expanded(
                        child: _TeamStatBox(
                          label: 'Paid',
                          minor: totalTeamPaid,
                        ),
                      ),
                      Expanded(
                        child: _TeamStatBox(
                          label: 'Remaining',
                          minor: teamRemaining,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  // Per-member breakdown — includes all members involved
                  // (both those with shares and those who paid).
                  for (final memberId in <int>{
                    ...shareByMember.keys,
                    ...paidByMember.keys,
                  }.toList()..sort())
                    _TeamMemberRow(
                      name: widget.tripView.memberById(memberId).name,
                      share: shareByMember[memberId] ?? 0,
                      paid: paidByMember[memberId] ?? 0,
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: teamMembers.when(
              data: (members) {
                if (members.isEmpty) {
                  return Text(
                    'No members yet',
                    style: theme.textTheme.captionMuted,
                  );
                }
                return Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final member in members)
                      Chip(
                        avatar: MemberAvatar(member.name, radius: 10),
                        label: Text(
                          member.name,
                          style: theme.textTheme.labelMedium,
                        ),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                );
              },
              loading: () =>
                  Text('Loading...', style: theme.textTheme.captionMuted),
              error: (_, _) =>
                  Text('No members', style: theme.textTheme.captionMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamStatBox extends StatelessWidget {
  const _TeamStatBox({required this.label, required this.minor});

  final String label;
  final int minor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.statLabel),
        const SizedBox(height: 4),
        MoneyText(minor, style: theme.textTheme.statValue),
      ],
    );
  }
}

class _TeamMemberRow extends StatelessWidget {
  const _TeamMemberRow({
    required this.name,
    required this.share,
    required this.paid,
  });

  final String name;
  final int share;
  final int paid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final net = paid - share;
    final tone = net > 0
        ? StatusTone.success
        : net < 0
        ? StatusTone.warning
        : StatusTone.neutral;
    final label = net > 0
        ? 'Receives'
        : net < 0
        ? 'Owes'
        : 'Balanced';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          MemberAvatar(name, radius: 10),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              style: theme.textTheme.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          MoneyText(share, style: theme.textTheme.bodyMuted),
          const SizedBox(width: 8),
          MoneyText(paid, style: theme.textTheme.bodyMedium),
          const SizedBox(width: 8),
          StatusChip(label, tone: tone),
        ],
      ),
    );
  }
}
