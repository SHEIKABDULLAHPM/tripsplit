import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/calculations/balances.dart';
import '../../../core/calculations/settlements.dart';
import '../../../core/utils/streams.dart';
import '../../../database/app_database.dart';
import '../../../database/domain_mappers.dart';
import '../../../injection/database_providers.dart';
import '../../contributions/domain/contribution.dart';
import '../../expenses/domain/expense.dart';
import '../../expenses/domain/expense_payment.dart';
import '../../expenses/domain/expense_share.dart';
import '../../journey/domain/journey.dart';
import '../../members/domain/member.dart';
import '../../settlements/domain/settlement.dart';
import '../domain/trip.dart';

/// Summary shown on the home screen card for a single trip.
class TripCardData {
  const TripCardData({
    required this.trip,
    required this.memberCount,
    required this.expenseCount,
    required this.contributionTotalMinor,
    required this.spentMinor,
  });

  final Trip trip;
  final int memberCount;
  final int expenseCount;
  final int contributionTotalMinor;
  final int spentMinor;

  int get remainingBudgetMinor => trip.totalBudgetMinor - spentMinor;
}

/// An expense together with its split shares.
class ExpenseWithShares {
  const ExpenseWithShares({required this.expense, required this.shares});

  final Expense expense;
  final List<ExpenseShare> shares;
}

/// Fully resolved view of one trip: every source transaction plus the derived
/// balances and settlement plan, ready for presentation.
class TripView {
  const TripView({
    required this.trip,
    required this.members,
    required this.expenses,
    required this.contributions,
    required this.settlements,
    required this.payments,
    required this.balances,
    required this.settlementPlan,
  });

  final Trip trip;
  final List<Member> members;
  final List<ExpenseWithShares> expenses;
  final List<Contribution> contributions;
  final List<Settlement> settlements;

  /// Who paid what (the authoritative payment breakdown, when recorded).
  final List<ExpensePayment> payments;

  final BalanceResult balances;
  final SettlementResult settlementPlan;

  Member memberById(int id) => members.firstWhere(
    (m) => m.id == id,
    orElse: () =>
        Member(id: id, tripId: 0, name: '?', createdAt: DateTime(2024)),
  );

  int contributionTotalFor(int memberId) => contributions
      .where((c) => c.memberId == memberId)
      .fold<int>(0, (sum, c) => sum + c.amountMinor);

  /// Cash actually transferred from [fromMemberId] to [toMemberId] so far.
  int settlementPaidBetween(int fromMemberId, int toMemberId) =>
      SettlementCalculator.totalPaidBetween(
        settlements,
        fromMemberId: fromMemberId,
        toMemberId: toMemberId,
      );

  /// Cash still owed between the pair according to the live plan.
  int settlementRemainingBetween(int fromMemberId, int toMemberId) =>
      SettlementCalculator.outstandingBetween(
        settlementPlan.suggestions,
        fromMemberId: fromMemberId,
        toMemberId: toMemberId,
      );

  /// The pair's current, fully-up-to-date obligation (paid + still owed).
  int settlementObligationBetween(int fromMemberId, int toMemberId) =>
      SettlementCalculator.liveObligationBetween(
        settlements,
        settlementPlan.suggestions,
        fromMemberId: fromMemberId,
        toMemberId: toMemberId,
      );
}

/// Latest summaries for the home screen trip list.
final homeViewProvider = StreamProvider.autoDispose<List<TripCardData>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return mapLatest<Object?, List<TripCardData>>([
    db.tripDao.watchAll(),
    db.memberDao.watchAll(),
    db.contributionDao.watchAll(),
    db.expenseDao.watchAll(),
  ], _buildHomeCards);
});

List<TripCardData> _buildHomeCards(List<Object?> values) {
  final trips = values[0] as List<TripRow>;
  final members = values[1] as List<MemberRow>;
  final contributions = values[2] as List<ContributionRow>;
  final expenses = values[3] as List<ExpenseRow>;
  final cards = <TripCardData>[];
  for (final trip in trips) {
    final contributionTotal = contributions
        .where((contribution) => contribution.tripId == trip.id)
        .fold<int>(0, (sum, contribution) => sum + contribution.amountMinor);
    final tripExpenses = expenses.where((expense) => expense.tripId == trip.id);
    final spent = tripExpenses.fold<int>(
      0,
      (sum, expense) =>
          sum + (expense.amountMinor - expense.externalAmountMinor),
    );

    cards.add(
      TripCardData(
        trip: trip.toDomain(),
        memberCount: members.where((member) => member.tripId == trip.id).length,
        expenseCount: tripExpenses.length,
        contributionTotalMinor: contributionTotal,
        spentMinor: spent,
      ),
    );
  }
  return cards;
}

/// The trip's journey state: locations, ordered travel segments and every
/// stored participation override, combined so screens can derive default
/// participants for segment-based expenses.
class JourneyView {
  const JourneyView({
    required this.locations,
    required this.segments,
    required this.participations,
  });

  final List<TripLocation> locations;
  final List<TravelSegment> segments;
  final List<MemberParticipation> participations;

  bool get isEmpty => segments.isEmpty && locations.isEmpty;

  TripLocation? locationById(int id) {
    for (final location in locations) {
      if (location.id == id) {
        return location;
      }
    }
    return null;
  }
}

/// Reactive combined journey state for a trip.
///
/// Kept alive (not `autoDispose`) so switching between trip tabs does not
/// tear down and reload per-trip streams, avoiding spinner flicker.
final journeyViewProvider = StreamProvider.family<JourneyView?, int>((
  ref,
  tripId,
) {
  final journeyRepository = ref.watch(journeyRepositoryProvider);
  return mapLatest<Object?, JourneyView>(
    [
      journeyRepository.watchLocations(tripId),
      journeyRepository.watchSegments(tripId),
      journeyRepository.watchParticipations(tripId),
    ],
    (values) => JourneyView(
      locations: values[0] as List<TripLocation>,
      segments: values[1] as List<TravelSegment>,
      participations: values[2] as List<MemberParticipation>,
    ),
  );
});

/// Teams available for a trip.
final teamsForTripProvider = StreamProvider.family<List<Team>, int>(
  (ref, tripId) => ref.watch(teamRepositoryProvider).watchTeams(tripId),
);

/// Reactive list of members belonging to a specific team.
final teamMembersProvider = StreamProvider.autoDispose
    .family<List<Member>, int>(
      (ref, teamId) =>
          ref.watch(teamRepositoryProvider).watchTeamMembers(teamId),
    );

/// Fully resolved, reactive view of a single trip.
///
/// Kept alive (not `autoDispose`) so switching between trip tabs does not
/// tear down and reload per-trip streams, avoiding spinner flicker.
final tripViewProvider = StreamProvider.family<TripView?, int>((ref, tripId) {
  final db = ref.watch(appDatabaseProvider);
  return _buildTripView(db, tripId);
});

Stream<TripView?> _buildTripView(AppDatabase db, int tripId) =>
    mapLatest<Object?, TripView?>([
      db.tripDao.watchById(tripId),
      db.memberDao.watchByTrip(tripId),
      db.expenseDao.watchByTrip(tripId),
      db.expenseDao.watchSharesByTrip(tripId),
      db.contributionDao.watchByTrip(tripId),
      db.settlementDao.watchByTrip(tripId),
      db.journeyDao.watchPaymentsByTrip(tripId),
      db.expenseDao.watchTeamLinksByTrip(tripId),
      db.journeyDao.watchTeamMembersByTrip(tripId),
    ], _resolveTripView);

TripView? _resolveTripView(List<Object?> values) {
  final tripRow = values[0] as TripRow?;
  if (tripRow == null) {
    return null;
  }

  final members = (values[1] as List<MemberRow>)
      .map((row) => row.toDomain())
      .toList();
  final expenseRows = values[2] as List<ExpenseRow>;
  final allShares = (values[3] as List<ExpenseShareRow>)
      .map((share) => share.toDomain())
      .toList();
  final contributions = (values[4] as List<ContributionRow>)
      .map((row) => row.toDomain())
      .toList();
  final settlements = (values[5] as List<SettlementRow>)
      .map((row) => row.toDomain())
      .toList();
  final payments = (values[6] as List<ExpensePaymentRow>)
      .map((row) => row.toDomain())
      .toList();

  final teamIdsByExpense = <int, List<int>>{};
  for (final link in values[7] as List<ExpenseTeamRow>) {
    teamIdsByExpense.putIfAbsent(link.expenseId, () => []).add(link.teamId);
  }
  Expense toExpense(ExpenseRow row) =>
      row.toDomain().copyWith(teamIds: teamIdsByExpense[row.id] ?? const []);

  final expenseViews = <ExpenseWithShares>[];
  final sharesByExpense = <int, List<ExpenseShare>>{};
  for (final share in allShares) {
    sharesByExpense.putIfAbsent(share.expenseId, () => []).add(share);
  }
  // Map each expense row once; the same domain objects feed both the views
  // and the balance/settlement calculations to avoid a duplicate pass on the
  // hottest refresh path in the app.
  final allExpenses = expenseRows.map(toExpense).toList();
  for (final expense in allExpenses) {
    expenseViews.add(
      ExpenseWithShares(
        expense: expense,
        shares: sharesByExpense[expense.id] ?? const [],
      ),
    );
  }
  final trip = tripRow.toDomain();

  // Real team membership (team_members rows), reactive to member joins/leaves.
  // The settlement calculator uses this to keep non-payer participants within
  // their own team, instead of the previous expense-share-derived map which
  // treated every participant of a multi-team expense as a member of every
  // linked team and let cross-team edges leak back in.
  final teamMemberIds = <int, Set<int>>{};
  for (final membership in values[8] as List<TeamMemberRow>) {
    teamMemberIds.putIfAbsent(membership.teamId, () => {}).add(
      membership.memberId,
    );
  }

  final settlementPlan = SettlementCalculator.calculate(
    expenses: allExpenses,
    shares: allShares,
    settlements: settlements,
    payments: payments,
    teamMemberIds: teamMemberIds.isNotEmpty ? teamMemberIds : null,
  );

  return TripView(
    trip: trip,
    members: members,
    expenses: expenseViews,
    contributions: contributions,
    settlements: settlements,
    payments: payments,
    balances: BalanceCalculator.calculate(
      tripBudgetMinor: trip.totalBudgetMinor,
      contributions: contributions,
      expenses: allExpenses,
      shares: allShares,
      settlements: settlements,
      payments: payments,
      postSettlementOutstanding: settlementPlan.totalOutstanding,
    ),
    settlementPlan: settlementPlan,
  );
}
