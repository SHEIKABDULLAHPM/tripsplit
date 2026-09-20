/// Application-wide constants.
///
/// This file intentionally contains only static, framework-level constants.
/// Do not place feature-specific values here.
abstract final class AppConstants {
  static const String appName = 'TripSplit';
  static const String appTagline = 'Share trip expenses, fairly.';

  /// Database file name used by the local SQLite (Drift) database.
  static const String databaseFileName = 'tripsplit.db';

  /// Current database schema version.
  ///
  /// Bump this value together with the migration steps registered in
  /// `AppDatabase.migration` when the schema changes.
  static const int databaseSchemaVersion = 7;
}
