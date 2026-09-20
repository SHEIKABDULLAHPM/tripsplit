import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_spacing.dart';
import '../../app/widgets/edit_trip_dialog.dart';
import '../../app/widgets/trip_shell.dart';
import '../../features/trips/data/trip_views.dart';
import '../router.dart';

/// "More" tab: aggregated less-frequent trip actions.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key, required this.tripId});

  final int tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(tripViewProvider(tripId));
    final trip = view.value?.trip;

    return Scaffold(
      body: TripShell(
        tripId: tripId,
        selectedIndex: 3,
        child: Column(
          children: [
            AppBar(title: const Text('More')),
            Expanded(
              child: SafeArea(
                bottom: false,
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  children: [
                    _MoreTile(
                      icon: Icons.people_outline,
                      title: 'People',
                      subtitle: 'Members, contributions & balances',
                      onTap: () => context.push(AppRoutes.people(tripId)),
                    ),
                    _MoreTile(
                      icon: Icons.route_outlined,
                      title: 'Journey',
                      subtitle: 'Route, segments & who travels',
                      onTap: () => context.push(AppRoutes.journey(tripId)),
                    ),
                    _MoreTile(
                      icon: Icons.groups_outlined,
                      title: 'Teams',
                      subtitle: 'Organize members into groups',
                      onTap: () => context.push(AppRoutes.teams(tripId)),
                    ),
                    _MoreTile(
                      icon: Icons.account_balance_wallet_outlined,
                      title: 'Balances',
                      subtitle: 'Who owes whom',
                      onTap: () => context.push(AppRoutes.balances(tripId)),
                    ),
                    _MoreTile(
                      icon: Icons.sticky_note_2_outlined,
                      title: 'Notes',
                      subtitle: 'Trip reminders & details',
                      onTap: () => context.push(AppRoutes.notes(tripId)),
                    ),
                    const Divider(height: AppSpacing.md),
                    _MoreTile(
                      icon: Icons.favorite_outline,
                      title: 'Support TripSplit',
                      subtitle: 'Voluntary funding to keep TripSplit free',
                      onTap: () => context.push(AppRoutes.funding),
                    ),
                    if (trip != null) ...[
                      const Divider(height: AppSpacing.md),
                      _MoreTile(
                        icon: Icons.edit_outlined,
                        title: 'Trip settings',
                        subtitle: 'Edit name, budget & dates',
                        onTap: () => showDialog<void>(
                          context: context,
                          builder: (_) => EditTripDialog(trip: trip),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }
}
