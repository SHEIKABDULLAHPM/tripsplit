import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../injection/riverpod_providers.dart';
import 'theme/app_theme.dart';

/// Root widget of TripSplit.
///
/// Wires the Riverpod provider scope and the GoRouter navigation graph into
/// the widget tree.
class TripSplitApp extends ConsumerWidget {
  const TripSplitApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'TripSplit',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
    );
  }
}
