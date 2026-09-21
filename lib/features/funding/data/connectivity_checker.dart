import 'package:connectivity_plus/connectivity_plus.dart';

/// Abstract interface for checking network connectivity.
///
/// Testable: tests inject a fake that never touches platform channels.
abstract interface class ConnectivityChecker {
  /// Returns true if any network connection is available.
  Future<bool> hasConnection();
}

/// Production implementation backed by the connectivity_plus plugin.
class ConnectivityPlusChecker implements ConnectivityChecker {
  ConnectivityPlusChecker({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<bool> hasConnection() async {
    final results = await _connectivity.checkConnectivity();
    return results.any((result) => result != ConnectivityResult.none);
  }
}
