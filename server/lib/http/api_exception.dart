/// Public error contract for the HTTP API.
///
/// Only [code] and [publicMessage] ever reach the client. Internal detail
/// (the cause, the failing component) belongs to the audit log, never to the
/// response, so stack traces and database internals are never disclosed.
library;

/// An API-level failure with a safe, client-presentable message.
class ApiException implements Exception {
  final int statusCode;
  final String code;
  final String publicMessage;
  final String? internalDetail;

  const ApiException(
    this.statusCode,
    this.code,
    this.publicMessage, {
    this.internalDetail,
  });

  /// Builds a JSON body safe to return to the client.
  Map<String, Object?> toJson() => {
    'error': {'code': code, 'message': publicMessage},
  };
}

/// Convenience constructors grouped under one class.
abstract final class ApiErrors {
  static ApiException badRequest(String message, {String? detail}) =>
      ApiException(400, 'invalid_request', message, internalDetail: detail);

  static ApiException unauthorized(String message) =>
      ApiException(401, 'unauthorized', message);

  static ApiException forbidden(String message) =>
      ApiException(403, 'forbidden', message);

  static ApiException notFound(String message) =>
      ApiException(404, 'not_found', message);

  static ApiException conflict(String code, String message, {String? detail}) =>
      ApiException(409, code, message, internalDetail: detail);

  static ApiException payloadTooLarge(String message) =>
      ApiException(413, 'payload_too_large', message);

  static ApiException unsupportedTerms(String message) =>
      ApiException(422, 'unsupported_terms_version', message);

  static ApiException serviceUnavailable(String message) =>
      ApiException(503, 'service_unavailable', message);

  static ApiException internal(String message, {String? detail}) =>
      ApiException(500, 'internal_error', message, internalDetail: detail);
}
