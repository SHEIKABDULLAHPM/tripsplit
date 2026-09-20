import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../router.dart';

/// A persistent bottom navigation bar for trip-level screens.
///
/// 4 tabs: Overview, Expenses, Settlements, More.
/// Contextual actions (Add Expense, Record Payment) live within their sections.
class TripShell extends StatelessWidget {
  const TripShell({
    super.key,
    required this.tripId,
    required this.child,
    this.selectedIndex = 0,
  });

  final int tripId;
  final Widget child;
  final int selectedIndex;

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.dashboard_outlined),
      selectedIcon: Icon(Icons.dashboard),
      label: 'Overview',
    ),
    NavigationDestination(
      icon: Icon(Icons.receipt_long_outlined),
      selectedIcon: Icon(Icons.receipt_long),
      label: 'Expenses',
    ),
    NavigationDestination(
      icon: Icon(Icons.swap_horiz_outlined),
      selectedIcon: Icon(Icons.swap_horiz),
      label: 'Settle',
    ),
    NavigationDestination(
      icon: Icon(Icons.more_horiz_outlined),
      selectedIcon: Icon(Icons.more_horiz),
      label: 'More',
    ),
  ];

  void _onTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go(AppRoutes.trip(tripId));
      case 1:
        context.go(AppRoutes.expenses(tripId));
      case 2:
        context.go(AppRoutes.settlements(tripId));
      case 3:
        context.go(AppRoutes.more(tripId));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        Expanded(child: child),
        SafeArea(
          bottom: true,
          child: NavigationBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: (index) => _onTap(context, index),
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            height: 64,
            indicatorColor: Theme.of(context).colorScheme.primaryContainer,
            destinations: _destinations,
          ),
        ),
      ],
    ),
  );
}
