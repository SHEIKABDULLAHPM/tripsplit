import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/daos/contribution_dao.dart';
import '../database/daos/expense_dao.dart';
import '../database/daos/journey_dao.dart';
import '../database/daos/member_dao.dart';
import '../database/daos/note_dao.dart';
import '../database/daos/settlement_dao.dart';
import '../database/daos/trip_dao.dart';
import '../features/contributions/data/contribution_repository_impl.dart';
import '../features/contributions/domain/contribution_repository.dart';
import '../features/expenses/data/expense_repository_impl.dart';
import '../features/expenses/domain/expense_repository.dart';
import '../features/journey/data/journey_repository_impl.dart';
import '../features/journey/domain/journey_repository.dart';
import '../features/members/data/member_repository_impl.dart';
import '../features/members/domain/member_repository.dart';
import '../features/notes/data/note_repository_impl.dart';
import '../features/notes/domain/note_repository.dart';
import '../features/settlements/data/settlement_repository_impl.dart';
import '../features/settlements/domain/settlement_repository.dart';
import '../features/teams/data/team_repository_impl.dart';
import '../features/teams/domain/team_repository.dart';
import '../features/trips/data/trip_repository_impl.dart';
import '../features/trips/domain/trip_repository.dart';

/// Provides the single [AppDatabase] instance for the application lifetime.
///
/// The database is lazily opened on first access and disposed when the
/// provider is invalidated (e.g. during a hot restart).
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.closeDatabase);
  return db;
});

/// Convenience providers for each DAO, derived from [appDatabaseProvider].

final tripDaoProvider = Provider<TripDao>(
  (ref) => ref.read(appDatabaseProvider).tripDao,
);
final memberDaoProvider = Provider<MemberDao>(
  (ref) => ref.read(appDatabaseProvider).memberDao,
);
final contributionDaoProvider = Provider<ContributionDao>(
  (ref) => ref.read(appDatabaseProvider).contributionDao,
);
final expenseDaoProvider = Provider<ExpenseDao>(
  (ref) => ref.read(appDatabaseProvider).expenseDao,
);
final settlementDaoProvider = Provider<SettlementDao>(
  (ref) => ref.read(appDatabaseProvider).settlementDao,
);
final journeyDaoProvider = Provider<JourneyDao>(
  (ref) => ref.read(appDatabaseProvider).journeyDao,
);
final noteDaoProvider = Provider<NoteDao>(
  (ref) => ref.read(appDatabaseProvider).noteDao,
);

/// Repository providers, the single entry point for feature code. Widgets and
/// controllers depend on repositories, never on DAOs directly.
final tripRepositoryProvider = Provider<TripRepository>(
  (ref) => TripRepositoryImpl(ref.read(appDatabaseProvider)),
);
final memberRepositoryProvider = Provider<MemberRepository>(
  (ref) => MemberRepositoryImpl(ref.read(appDatabaseProvider)),
);
final contributionRepositoryProvider = Provider<ContributionRepository>(
  (ref) => ContributionRepositoryImpl(ref.read(appDatabaseProvider)),
);
final expenseRepositoryProvider = Provider<ExpenseRepository>(
  (ref) => ExpenseRepositoryImpl(ref.read(appDatabaseProvider)),
);
final settlementRepositoryProvider = Provider<SettlementRepository>(
  (ref) => SettlementRepositoryImpl(ref.read(appDatabaseProvider)),
);
final journeyRepositoryProvider = Provider<JourneyRepository>(
  (ref) => JourneyRepositoryImpl(ref.read(appDatabaseProvider)),
);
final noteRepositoryProvider = Provider<NoteRepository>(
  (ref) => NoteRepositoryImpl(ref.read(appDatabaseProvider)),
);
final teamRepositoryProvider = Provider<TeamRepository>(
  (ref) => TeamRepositoryImpl(ref.read(appDatabaseProvider)),
);
