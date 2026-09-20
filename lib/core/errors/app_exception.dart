import 'package:sqlite3/sqlite3.dart' show SqliteException;

/// Base class for all TripSplit application errors.
///
/// All errors thrown by the application (UI, services, repositories) should
/// extend this class so that presentation code can rely on a single error
/// contract.
sealed class AppException implements Exception {
  const AppException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

/// Raised when the local (SQLite) database layer fails.
///
/// Wraps low-level [SqliteException]s so that callers never depend on the
/// underlying database library directly.
final class DatabaseException extends AppException {
  const DatabaseException(super.message, {super.cause, this.code});

  factory DatabaseException.fromSqlite(SqliteException error, {String? table}) {
    final context = table == null
        ? error.message
        : 'Error on table "$table": ${error.message}';
    return DatabaseException(
      'Database operation failed: $context',
      cause: error,
      code: error.resultCode,
    );
  }

  /// Optional native SQLite error code, when available.
  final int? code;
}

/// Raised when user input or a domain invariant fails validation.
final class ValidationException extends AppException {
  const ValidationException(super.message, {super.cause});
}

/// Raised when a repository cannot complete an operation.
///
/// Repositories translate database and validation errors into a single
/// repository-level contract for the domain layer.
final class RepositoryException extends AppException {
  const RepositoryException(super.message, {super.cause});
}
