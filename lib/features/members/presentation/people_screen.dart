import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/calculations/money.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/widgets/app_confirmation_dialog.dart';
import '../../../core/widgets/app_money_field.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/member_avatar.dart';
import '../../../core/widgets/money_text.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../injection/database_providers.dart';
import '../../contributions/domain/contribution.dart';
import '../../members/domain/member.dart';
import '../../trips/data/trip_views.dart';

/// People screen shown at `/trip/:tripId/members`.
///
/// Lists trip members with their contribution, net position and key activity,
/// and offers adding/removing members and recording contributions via inline
/// bottom sheets.
class PeopleScreen extends ConsumerWidget {
  const PeopleScreen({super.key, required this.tripId});

  final int tripId;

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    int memberId,
    String name,
  ) async {
    final confirmed = await showAppConfirmation(
      context,
      title: 'Remove $name?',
      message:
          'Removing a member also removes their contributions. '
          'Members who have expenses or settlements cannot be removed.',
      confirmLabel: 'Remove',
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    try {
      await ref.read(memberRepositoryProvider).deleteById(memberId);
    } on AppException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  void _showQuickAddMember(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _QuickAddMemberSheet(tripId: tripId),
    );
  }

  void _showQuickRecordContribution(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _QuickRecordContributionSheet(tripId: tripId),
    );
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref, Member member) {
    final controller = TextEditingController(text: member.name);
    final formKey = GlobalKey<FormState>();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename member'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. Priya',
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Please enter a name'
                : null,
            onFieldSubmitted: (_) =>
                _submitRename(ctx, ref, member, controller, formKey),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                _submitRename(ctx, ref, member, controller, formKey),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitRename(
    BuildContext ctx,
    WidgetRef ref,
    Member member,
    TextEditingController controller,
    GlobalKey<FormState> formKey,
  ) async {
    if (!(formKey.currentState?.validate() ?? false)) {
      return;
    }
    final newName = controller.text.trim();
    if (newName == member.name) {
      Navigator.of(ctx).pop();
      return;
    }
    try {
      await ref
          .read(memberRepositoryProvider)
          .save(
            Member(
              id: member.id,
              tripId: member.tripId,
              name: newName,
              joinLocationId: member.joinLocationId,
              leaveLocationId: member.leaveLocationId,
              createdAt: member.createdAt,
            ),
          );
      if (ctx.mounted) {
        Navigator.of(ctx).pop();
      }
    } on AppException catch (error) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(
          ctx,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(tripViewProvider(tripId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('People')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-member-fab',
        onPressed: () => _showQuickAddMember(context, ref),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Add member'),
      ),
      body: SafeArea(
        bottom: true,
        child: AsyncValueView<TripView?>(
          value: view,
          onRetry: () => ref.invalidate(tripViewProvider(tripId)),
          isEmpty: (value) => value == null || value.members.isEmpty,
          empty: EmptyState(
            icon: Icons.people_outline,
            title: 'No members yet',
            message: 'Add members to start sharing expenses.',
            actionLabel: 'Add first member',
            onAction: () => _showQuickAddMember(context, ref),
          ),
          builder: (tripView) {
            if (tripView == null) {
              return const SizedBox.shrink();
            }
            final members = tripView.members;
            return RefreshIndicator(
              onRefresh: () {
                ref.invalidate(tripViewProvider(tripId));
                return ref.read(tripViewProvider(tripId).future);
              },
              child: ListView.separated(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.lg,
                ),
                itemCount: members.length + 1,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, index) {
                  if (index == members.length) {
                    return Column(
                      children: [
                        Card(
                          margin: EdgeInsets.zero,
                          child: ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.savings_outlined),
                            ),
                            title: const Text('Record a contribution'),
                            subtitle: const Text(
                              'Cash pooled into the trip budget',
                            ),
                            onTap: () =>
                                _showQuickRecordContribution(context, ref),
                          ),
                        ),
                        // Show existing contributions
                        if (tripView.contributions.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.md),
                          _ContributionsSummary(
                            tripView: tripView,
                            tripId: tripId,
                          ),
                        ],
                      ],
                    );
                  }
                  final member = members[index];
                  final contribution = tripView.contributionTotalFor(member.id);
                  final netLabel = _netLabelFor(tripView, member.id);
                  final netMinor = _netMinor(tripView, member.id);
                  final (actualPaid, expenseShare) = _metricsFor(
                    tripView,
                    member.id,
                  );
                  final tone = netMinor > 0
                      ? StatusTone.success
                      : netMinor < 0
                      ? StatusTone.warning
                      : StatusTone.neutral;

                  return Card(
                    margin: EdgeInsets.zero,
                    child: InkWell(
                      onTap: () => context.push(
                        AppRoutes.memberDetail(tripId, member.id),
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.md),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        member.name,
                                        style: theme.textTheme.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      MoneyText(
                                        contribution,
                                        style: theme.textTheme.bodyMuted,
                                      ),
                                    ],
                                  ),
                                ),
                                StatusChip(netLabel, tone: tone),
                                PopupMenuButton<String>(
                                  tooltip: 'Member options',
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(
                                      value: 'rename',
                                      child: Text('Rename'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Remove'),
                                    ),
                                  ],
                                  onSelected: (value) {
                                    switch (value) {
                                      case 'rename':
                                        _showRenameDialog(context, ref, member);
                                      case 'delete':
                                        _confirmDelete(
                                          context,
                                          ref,
                                          member.id,
                                          member.name,
                                        );
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            _MetricRow(
                              metrics: [
                                ('Actual paid', actualPaid),
                                ('Expense share', expenseShare),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  static (int, int) _metricsFor(TripView view, int memberId) {
    for (final balance in view.balances.members) {
      if (balance.memberId == memberId) {
        return (balance.actualPaid, balance.expenseShare);
      }
    }
    return (0, 0);
  }

  static String _netLabelFor(TripView view, int memberId) {
    for (final balance in view.balances.members) {
      if (balance.memberId == memberId) {
        return balance.netLabel;
      }
    }
    return 'Balanced';
  }

  static int _netMinor(TripView view, int memberId) {
    for (final balance in view.balances.members) {
      if (balance.memberId == memberId) {
        return balance.amountToPay - balance.amountToReceive;
      }
    }
    return 0;
  }
}

class _QuickAddMemberSheet extends ConsumerStatefulWidget {
  const _QuickAddMemberSheet({required this.tripId});

  final int tripId;

  @override
  ConsumerState<_QuickAddMemberSheet> createState() =>
      _QuickAddMemberSheetState();
}

class _QuickAddMemberSheetState extends ConsumerState<_QuickAddMemberSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _contributionController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _contributionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final name = _nameController.text.trim();
    final contributionMinor = _contributionController.text.trim().isEmpty
        ? 0
        : MoneyCalculator.parseToMinor(
            _contributionController.text,
            label: 'Contribution',
          );

    setState(() => _saving = true);
    try {
      final member = await ref
          .read(memberRepositoryProvider)
          .save(
            Member(
              id: 0,
              tripId: widget.tripId,
              name: name,
              createdAt: DateTime.now(),
            ),
          );
      if (contributionMinor > 0) {
        await ref
            .read(contributionRepositoryProvider)
            .save(
              Contribution(
                id: 0,
                tripId: widget.tripId,
                memberId: member.id,
                amountMinor: contributionMinor,
                note: null,
                createdAt: DateTime.now(),
              ),
            );
      }
      if (mounted) {
        Navigator.of(context).pop();
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
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl + bottomInset,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add member', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Priya',
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Please enter a name'
                  : null,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppMoneyField(
              controller: _contributionController,
              label: 'First contribution (optional)',
              hintText: 'e.g. 1000',
              constraint: AppMoneyConstraint.optional,
              errorLabel: 'Contribution',
              negativeMessage: 'Contribution cannot be negative.',
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: _saving ? null : _submit,
              icon: const Icon(Icons.check),
              label: const Text('Add member'),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickRecordContributionSheet extends ConsumerStatefulWidget {
  const _QuickRecordContributionSheet({required this.tripId});

  final int tripId;

  @override
  ConsumerState<_QuickRecordContributionSheet> createState() =>
      _QuickRecordContributionSheetState();
}

class _QuickRecordContributionSheetState
    extends ConsumerState<_QuickRecordContributionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  int? _memberId;
  bool _saving = false;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final amountMinor = MoneyCalculator.parseToMinor(
      _amountController.text,
      label: 'Contribution',
    );
    setState(() => _saving = true);
    try {
      await ref
          .read(contributionRepositoryProvider)
          .save(
            Contribution(
              id: 0,
              tripId: widget.tripId,
              memberId: _memberId!,
              amountMinor: amountMinor,
              note: _noteController.text.trim().isEmpty
                  ? null
                  : _noteController.text.trim(),
              createdAt: DateTime.now(),
            ),
          );
      if (mounted) {
        Navigator.of(context).pop();
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
    final view = ref.watch(tripViewProvider(widget.tripId));
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl + bottomInset,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Record contribution',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.lg),
            AsyncValueView<TripView?>(
              value: view,
              onRetry: () => ref.invalidate(tripViewProvider(widget.tripId)),
              isEmpty: (value) => value == null || value.members.isEmpty,
              empty: const Text('Add a member first.'),
              builder: (tripView) {
                if (tripView == null) {
                  return const Text('Add a member first.');
                }
                _memberId ??= tripView.members.first.id;
                return DropdownButtonFormField<int>(
                  initialValue: _memberId,
                  decoration: const InputDecoration(labelText: 'Member'),
                  items: [
                    for (final member in tripView.members)
                      DropdownMenuItem(
                        value: member.id,
                        child: Text(member.name),
                      ),
                  ],
                  onChanged: (value) => setState(() => _memberId = value),
                  validator: (value) =>
                      value == null ? 'Select a member' : null,
                );
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            AppMoneyField(
              controller: _amountController,
              label: 'Amount',
              hintText: 'e.g. 1000',
              constraint: AppMoneyConstraint.requiredPositive,
              errorLabel: 'Contribution',
              autofocus: true,
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
              onPressed: _saving ? null : _submit,
              icon: const Icon(Icons.check),
              label: const Text('Save contribution'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.metrics});

  final List<(String, int)> metrics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        for (var i = 0; i < metrics.length; i++) ...[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(metrics[i].$1, style: theme.textTheme.captionMuted),
                const SizedBox(height: 1),
                MoneyText(metrics[i].$2, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
          if (i != metrics.length - 1) const SizedBox(width: AppSpacing.lg),
        ],
      ],
    );
  }
}

class _ContributionsSummary extends ConsumerWidget {
  const _ContributionsSummary({required this.tripView, required this.tripId});

  final TripView tripView;
  final int tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final contributions = tripView.contributions
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Contributions',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            for (final c in contributions) ...[
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: MemberAvatar(
                  _memberName(c.memberId, tripView),
                  radius: 14,
                ),
                title: Text(
                  _memberName(c.memberId, tripView),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: c.note != null
                    ? Text(
                        c.note!,
                        style: theme.textTheme.captionMuted,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 96),
                      child: MoneyText(
                        c.amountMinor,
                        style: theme.textTheme.statValue,
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Actions',
                      onSelected: (action) =>
                          _handleAction(context, ref, action, c),
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'edit', child: Text('Edit')),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _memberName(int memberId, TripView view) {
    for (final m in view.members) {
      if (m.id == memberId) return m.name;
    }
    return '?';
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
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(error.message)));
          }
        }
      }
    } else if (action == 'delete') {
      final confirmed = await showAppConfirmation(
        context,
        title: 'Delete contribution?',
        message:
            'This removes the ${MoneyCalculator.format(contribution.amountMinor)} contribution from ${_memberName(contribution.memberId, tripView)}.',
        confirmLabel: 'Delete',
      );
      if (confirmed && context.mounted) {
        try {
          await ref
              .read(contributionRepositoryProvider)
              .deleteById(contribution.id);
        } on AppException catch (error) {
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(error.message)));
          }
        }
      }
    }
  }
}
