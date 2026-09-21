import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/funding_exception.dart';

/// Minimal HTTP client for the funding service.
///
/// Uses the Dart [HttpClient] from `dart:io`, so funding's transport stack
/// stays isolated from the offline trip database. The only external dependency
/// funding adds is razorpay_flutter, used solely for the hosted checkout UI.
class FundingApiClient {
  FundingApiClient({required String baseUrl, Duration? timeout})
    : baseUri = Uri.parse(baseUrl),
      timeout = timeout ?? const Duration(seconds: 20);

  final Uri baseUri;
  final Duration timeout;

  static const int _connectTimeoutMs = 8000;

  /// Performs a lightweight GET request to verify the server is reachable.
  ///
  /// Returns true only when the server responds with a successful status.
  /// This is intentionally cheap — it reuses the same connection stack as
  /// the real API calls.
  Future<bool> checkConnectivity() async {
    fundingLog('Checking connectivity to ${baseUri.resolve('/health')}');
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: _connectTimeoutMs);
    try {
      final request = await client.getUrl(baseUri.resolve('/health'));
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      await response.drain<void>();
      final ok = response.statusCode >= 200 && response.statusCode < 400;
      fundingLog('Connectivity check: status=${response.statusCode} ok=$ok');
      return ok;
    } on SocketException catch (e) {
      fundingLogError('Connectivity check failed: SocketException', e);
      return false;
    } on HttpException catch (e) {
      fundingLogError('Connectivity check failed: HttpException', e);
      return false;
    } on TimeoutException catch (e) {
      fundingLogError('Connectivity check failed: TimeoutException', e);
      return false;
    } on OSError catch (e) {
      fundingLogError('Connectivity check failed: OSError', e);
      return false;
    } catch (e) {
      fundingLogError('Connectivity check failed: ${e.runtimeType}', e);
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> post(String path, Map<String, Object?> body) =>
      _request('POST', path, body: body);

  Future<Map<String, dynamic>> get(String path) => _request('GET', path);

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    final url = baseUri.resolve(path);
    fundingLog('$method $url');
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: _connectTimeoutMs);
    try {
      final request = await client.openUrl(method, url);
      request.headers.contentType = ContentType.json;
      if (body != null) {
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(timeout);
      final payload = await response.transform(utf8.decoder).join();
      fundingLog('Response: status=${response.statusCode}');

      final decoded = payload.isEmpty
          ? const <String, dynamic>{}
          : jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) {
        fundingLogError('Malformed response body (not a JSON object)');
        throw const FundingException(
          FundingFailureKind.malformedResponse,
          'Unexpected funding response.',
        );
      }
      if (response.statusCode >= 400) {
        final error = decoded['error'];
        final message = error is Map<String, dynamic>
            ? error['message'] as String? ?? 'Funding request failed.'
            : 'Funding request failed.';
        fundingLogError(
          'Server error: status=${response.statusCode} message=$message',
        );
        throw FundingException(FundingFailureKind.server, message);
      }
      fundingLog('Request succeeded');
      return decoded;
    } on TimeoutException {
      fundingLogError('Request timed out: $method $url');
      throw const FundingException(FundingFailureKind.timeout, fundingTimedOut);
    } on SocketException catch (e) {
      fundingLogError('SocketException: $method $url — ${e.message}', e);
      throw const FundingException(
        FundingFailureKind.serverUnreachable,
        fundingServerUnavailable,
      );
    } on HttpException catch (e) {
      fundingLogError('HttpException: $method $url — ${e.message}', e);
      throw const FundingException(
        FundingFailureKind.serverUnreachable,
        fundingServerUnavailable,
      );
    } on FundingException {
      rethrow;
    } catch (e) {
      fundingLogError(
        'Unexpected error: $method $url — ${e.runtimeType}: $e',
        e,
      );
      throw const FundingException(
        FundingFailureKind.serverUnreachable,
        fundingServerUnavailable,
      );
    } finally {
      client.close(force: true);
    }
  }
}
