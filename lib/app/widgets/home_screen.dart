import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/calculations/money.dart';
import '../../core/errors/app_exception.dart';
import '../../core/widgets/app_confirmation_dialog.dart';
import '../../core/widgets/async_value_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../features/trips/data/trip_views.dart';
import '../../features/trips/domain/trip.dart';
import '../../injection/database_providers.dart';
import '../router.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'brand_lockup.dart';
import 'edit_trip_dialog.dart';

/// Landing screen shown at `/`.
///
/// Lists every trip as a summary card with budget, spending, member and
/// expense counts, plus a primary action to create a new trip. The overflow
/// menu replays the onboarding tour for anyone who wants to see it again.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(homeViewProvider);

    return Scaffold(
      appBar: AppBar(
        // Persistent brand presence: the official mark alone in the leading
        // slot, keeping the title contextual ("Trips").
        leadingWidth: 44,
        leading: const Center(child: TripSplitMark(size: 28)),
        title: const Text('Trips'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Menu',
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'tour') {
                context.go(AppRoutes.onboarding);
              } else if (value == 'funding') {
                context.push(AppRoutes.funding);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'funding',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.favorite_outline),
                  title: Text('Support TripSplit'),
                ),
              ),
              PopupMenuItem(
                value: 'tour',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.help_outline),
                  title: Text('Show onboarding tour'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        bottom: true,
        child: AsyncValueView<List<TripCardData>>(
          value: trips,
          onRetry: () => ref.invalidate(homeViewProvider),
          isEmpty: (cards) => cards.isEmpty,
          empty: const EmptyState(
            icon: Icons.luggage,
            title: 'No trips yet',
            message: 'Create your first trip to start sharing expenses.',
          ),
          builder: (cards) => ListView.builder(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenHorizontal,
              vertical: AppSpacing.screenVertical,
            ),
            itemCount: cards.length,
            itemBuilder: (context, index) {
              final card = cards[index];
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index == cards.length - 1 ? 0 : AppSpacing.md,
                ),
                child: _TripCard(card: card),
              );
            },
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go(AppRoutes.createTrip),
        icon: const Icon(Icons.add),
        label: const Text('Create trip'),
      ),
    );
  }
}

class _TripCard extends ConsumerWidget {
  const _TripCard({required this.card});

  final TripCardData card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final trip = card.trip;
    final hasBudget = trip.totalBudgetMinor > 0;
    final budgetValue = hasBudget
        ? (card.spentMinor / trip.totalBudgetMinor).clamp(0.0, 1.0)
        : 0.0;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => context.go(AppRoutes.trip(trip.id)),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(trip.name, style: theme.textTheme.title),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Trip options',
                    padding: EdgeInsets.zero,
                    onSelected: (value) =>
                        _handleMenuAction(context, ref, value, trip),
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.lg,
                runSpacing: AppSpacing.sm,
                children: [
                  _Stat(
                    icon: Icons.people_outline,
                    label:
                        '${card.memberCount} member${card.memberCount == 1 ? '' : 's'}',
                  ),
                  _Stat(
                    icon: Icons.receipt_long_outlined,
                    label:
                        '${card.expenseCount} expense${card.expenseCount == 1 ? '' : 's'}',
                  ),
                  _Stat(
                    icon: Icons.savings_outlined,
                    label:
                        '${MoneyCalculator.formatNoSymbol(card.contributionTotalMinor)} contributed',
                  ),
                ],
              ),
              if (hasBudget) ...[
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: budgetValue,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Text(
                      '${MoneyCalculator.formatNoSymbol(card.spentMinor)} / '
                      '${MoneyCalculator.formatNoSymbol(trip.totalBudgetMinor)}',
                      style: theme.textTheme.labelMuted,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _handleMenuAction(
    BuildContext context,
    WidgetRef ref,
    String action,
    Trip trip,
  ) {
    switch (action) {
      case 'edit':
        _showEditDialog(context, ref, trip);
      case 'delete':
        _confirmDelete(context, ref, trip);
    }
  }

  void _showEditDialog(BuildContext context, WidgetRef ref, Trip trip) {
    showDialog<void>(
      context: context,
      builder: (_) => EditTripDialog(trip: trip),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Trip trip,
  ) async {
    final confirmed = await showAppConfirmation(
      context,
      title: 'Delete "${trip.name}"?',
      message:
          'This permanently removes the trip, all members, expenses, '
          'settlements, and journey data. This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ref.read(tripRepositoryProvider).deleteById(trip.id);
      if (context.mounted) {
        context.go(AppRoutes.home);
      }
    } on AppException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.xs),
          Flexible(child: Text(label, style: theme.textTheme.labelMuted)),
        ],
      ),
    );
  }
}
