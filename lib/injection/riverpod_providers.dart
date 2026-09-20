import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/router.dart';

/// Provides the application's navigation graph.
///
/// Making the router a provider (instead of a global) keeps it overridable in
/// tests and allows later integration with auth/state-driven redirects.
final appRouterProvider = Provider<GoRouter>((ref) => AppRouter.create());
