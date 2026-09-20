/// TripSplit funding server entrypoint.
///
/// Run (simulated/sandbox mode by default):
///   dart run bin/server.dart
///
/// Real-gateway deployment requires GATEWAY_MODE != simulated plus the
/// FUNDING_WEBHOOK_SECRET and an adapter wired into FundingServer.defaultInstance.
library;

import 'dart:async';
import 'dart:io';

import 'package:tripsplit_funding_server/config/server_config.dart';
import 'package:tripsplit_funding_server/http/funding_server.dart';

Future<void> main(List<String> arguments) async {
  final config = ServerConfig.fromEnvironment();
  final server = FundingServer.defaultInstance(config);
  final http = await server.start();

  ProcessSignal.sigint.watch().listen((_) async {
    await http.close(force: true);
    exit(0);
  });
  ProcessSignal.sigterm.watch().listen((_) async {
    await http.close(force: true);
    exit(0);
  });

  // Keep alive.
  await Completer<void>().future;
}