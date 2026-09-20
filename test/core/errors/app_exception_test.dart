import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;
import 'package:tripsplit/core/errors/app_exception.dart';

void main() {
  group('AppException', () {
    test('is an Exception', () {
      const error = DatabaseException('boom');
      expect(error, isA<Exception>());
    });

    test('carries a message and optional cause', () {
      final cause = StateError('root');
      const error = DatabaseException('boom');
      expect(error.message, 'boom');
      expect(error.toString(), contains('DatabaseException'));
      expect(cause, isA<StateError>());
    });
  });

  group('DatabaseException', () {
    test('is an AppException subtype', () {
      const error = DatabaseException('db failed');
      expect(error, isA<AppException>());
    });

    test('maps a low-level SqliteException', () {
      final sqlite = SqliteException(
        extendedResultCode: 1,
        message: 'table trips has no column named x',
      );
      final error = DatabaseException.fromSqlite(sqlite, table: 'trips');
      expect(error.message, contains('trips'));
      expect(error.code, 1);
      expect(error.cause, same(sqlite));
    });
  });

  group('ValidationException and RepositoryException', () {
    test('are AppException subtypes', () {
      const validation = ValidationException('invalid');
      const repository = RepositoryException('repo failed');
      expect(validation, isA<AppException>());
      expect(repository, isA<AppException>());
    });
  });
}
