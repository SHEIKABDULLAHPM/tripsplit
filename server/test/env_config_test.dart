import 'dart:io';

import 'package:test/test.dart';
import 'package:tripsplit_funding_server/config/env_file.dart';
import 'package:tripsplit_funding_server/config/server_config.dart';

File _tempEnv(String contents) {
  final dir = Directory.systemTemp.createTempSync('tip-env-test-');
  addTearDown(() => dir.deleteSync(recursive: true));
  final file = File('${dir.path}/.env');
  file.writeAsStringSync(contents);
  return file;
}

void main() {
  group('effectiveEnvironment', () {
    test('uses only the provided environment when no file is found', () {
      final env = effectiveEnvironment(
        path: '/nonexistent/path/.env',
        platform: const {'FUNDING_ENV': 'staging'},
      );
      expect(env, {'FUNDING_ENV': 'staging'});
    });

    test('platform environment wins over .env file defaults', () {
      final file = _tempEnv('RAZORPAY_KEY_ID=rzp_test_file\nPORT=9000\n');
      final env = effectiveEnvironment(
        path: file.path,
        platform: const {'PORT': '8080'},
      );
      expect(env['RAZORPAY_KEY_ID'], 'rzp_test_file');
      expect(env['PORT'], '8080');
    });

    test('parses quotes, export prefix, comments and blank lines', () {
      final file = _tempEnv('''
# Secret keys go here.

export RAZORPAY_KEY_ID="rzp_test_quoted"
RAZORPAY_WEBHOOK_SECRET='whsec'
RAZORPAY_KEY_SECRET=pla.in_secret
''');
      final env = effectiveEnvironment(path: file.path, platform: const {});
      expect(env['RAZORPAY_KEY_ID'], 'rzp_test_quoted');
      expect(env['RAZORPAY_WEBHOOK_SECRET'], 'whsec');
      expect(env['RAZORPAY_KEY_SECRET'], 'pla.in_secret');
    });

    test('rejects malformed lines and keys', () {
      final file = _tempEnv('THIS IS NOT A KEY VALUE PAIR\n');
      expect(
        () => effectiveEnvironment(path: file.path, platform: const {}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => effectiveEnvironment(path: file.path, platform: const {}),
        throwsA(predicate<FormatException>((e) => e.message.contains('.env'))),
      );
    });
  });

  group('ServerConfig.fromEnvironment', () {
    test('defaults to simulated mode without any secrets', () {
      final config = ServerConfig.fromEnvironment(
        envFilePath: '/nonexistent/path/.env',
        environment: const {},
      );
      expect(config.gatewayMode, 'simulated');
      expect(config.isSimulated, isTrue);
      expect(config.razorpayKeyId, isNull);
      expect(config.razorpayKeySecret, isNull);
      expect(config.razorpayApiBase, 'https://api.razorpay.com');
      expect(config.environment, 'test');
      expect(config.port, 8080);
      expect(config.dbPath, 'funding.sqlite3');
    });

    test('requires the full secret set in razorpay mode', () {
      expect(
        () => ServerConfig.fromEnvironment(
          envFilePath: '/nonexistent/path/.env',
          environment: const {'GATEWAY_MODE': 'razorpay'},
        ),
        throwsStateError,
      );
      expect(
        () => ServerConfig.fromEnvironment(
          envFilePath: '/nonexistent/path/.env',
          environment: const {
            'GATEWAY_MODE': 'razorpay',
            'RAZORPAY_KEY_ID': 'rzp_test_1',
            'RAZORPAY_KEY_SECRET': 'secret-1',
          },
        ),
        throwsStateError,
      );
    });

    test('reads razorpay keys from the environment', () {
      final config = ServerConfig.fromEnvironment(
        envFilePath: '/nonexistent/path/.env',
        environment: const {
          'GATEWAY_MODE': 'razorpay',
          'FUNDING_ENV': 'development',
          'RAZORPAY_KEY_ID': 'rzp_test_1',
          'RAZORPAY_KEY_SECRET': 'secret-1',
          'RAZORPAY_WEBHOOK_SECRET': 'whsec-1',
          'RAZORPAY_API_BASE': 'https://mock.razorpay.in',
          'DATABASE_URL': 'file:my-ledger.sqlite3',
        },
      );
      expect(config.isSimulated, isFalse);
      expect(config.environment, 'development');
      expect(config.razorpayKeyId, 'rzp_test_1');
      expect(config.razorpayKeySecret, 'secret-1');
      expect(config.webhookSecret, 'whsec-1');
      expect(config.razorpayApiBase, 'https://mock.razorpay.in');
      expect(config.dbPath, 'my-ledger.sqlite3');
    });

    test('reads razorpay keys from a .env file', () {
      final file = _tempEnv('''
GATEWAY_MODE=razorpay
RAZORPAY_KEY_ID=rzp_test_file
RAZORPAY_KEY_SECRET=secret_file
RAZORPAY_WEBHOOK_SECRET=whsec_file
''');
      final config = ServerConfig.fromEnvironment(
        envFilePath: file.path,
        environment: const {},
      );
      expect(config.razorpayKeyId, 'rzp_test_file');
      expect(config.razorpayKeySecret, 'secret_file');
      expect(config.webhookSecret, 'whsec_file');
    });

    test('rejects remote DATABASE_URL', () {
      expect(
        () => ServerConfig.fromEnvironment(
          envFilePath: '/nonexistent/path/.env',
          environment: const {
            'GATEWAY_MODE': 'razorpay',
            'RAZORPAY_KEY_ID': 'rzp_test_1',
            'RAZORPAY_KEY_SECRET': 'secret-1',
            'RAZORPAY_WEBHOOK_SECRET': 'whsec-1',
            'DATABASE_URL': 'https://db.example.com/x',
          },
        ),
        throwsStateError,
      );
    });
  });
}
