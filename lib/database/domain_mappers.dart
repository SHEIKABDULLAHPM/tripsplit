import '../features/contributions/domain/contribution.dart';
import '../features/expenses/domain/expense.dart';
import '../features/expenses/domain/expense_payment.dart';
import '../features/expenses/domain/expense_scope.dart';
import '../features/expenses/domain/expense_share.dart';
import '../features/journey/domain/journey.dart';
import '../features/members/domain/member.dart';
import '../features/notes/domain/note.dart';
import '../features/settlements/domain/settlement.dart';
import '../features/trips/domain/trip.dart';
import 'app_database.dart';

extension TripRowMapper on TripRow {
  Trip toDomain() => Trip(
    id: id,
    name: name,
    description: description,
    currencyCode: currencyCode,
    startDate: startDate,
    endDate: endDate,
    startLocation: startLocation,
    totalBudgetMinor: totalBudgetMinor,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension MemberRowMapper on MemberRow {
  Member toDomain() => Member(
    id: id,
    tripId: tripId,
    name: name,
    joinLocationId: joinLocationId,
    leaveLocationId: leaveLocationId,
    createdAt: createdAt,
  );
}

extension ContributionRowMapper on ContributionRow {
  Contribution toDomain() => Contribution(
    id: id,
    tripId: tripId,
    memberId: memberId,
    amountMinor: amountMinor,
    note: note,
    createdAt: createdAt,
  );
}

extension ExpenseRowMapper on ExpenseRow {
  Expense toDomain() => Expense(
    id: id,
    tripId: tripId,
    payerMemberId: payerMemberId,
    description: description,
    scope: ExpenseScopeName.fromApiValue(scope),
    segmentId: segmentId,
    teamId: teamId,
    amountMinor: amountMinor,
    externalAmountMinor: externalAmountMinor,
    category: category,
    spentAt: spentAt,
    createdAt: createdAt,
    updatedAt: updatedAt ?? createdAt,
  );
}

extension ExpenseShareRowMapper on ExpenseShareRow {
  ExpenseShare toDomain() => ExpenseShare(
    id: id,
    expenseId: expenseId,
    memberId: memberId,
    shareMinor: shareMinor,
  );
}

extension ExpensePaymentRowMapper on ExpensePaymentRow {
  ExpensePayment toDomain() => ExpensePayment(
    id: id,
    expenseId: expenseId,
    memberId: memberId,
    amountMinor: amountMinor,
    teamId: teamId,
  );
}

extension SettlementRowMapper on SettlementRow {
  Settlement toDomain() => Settlement(
    id: id,
    tripId: tripId,
    fromMemberId: fromMemberId,
    toMemberId: toMemberId,
    amountMinor: amountMinor,
    amountPaidMinor: amountPaidMinor,
    note: note,
    settledAt: settledAt,
    paidAt: paidAt,
    updatedAt: updatedAt ?? settledAt,
  );
}

extension NoteRowMapper on NoteRow {
  Note toDomain() => Note(
    id: id,
    tripId: tripId,
    title: title,
    body: body,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension LocationRowMapper on LocationRow {
  TripLocation toDomain() => TripLocation(id: id, tripId: tripId, name: name);
}

extension TravelSegmentRowMapper on TravelSegmentRow {
  TravelSegment toDomain() => TravelSegment(
    id: id,
    tripId: tripId,
    sequence: sequence,
    startLocationId: startLocationId,
    endLocationId: endLocationId,
    startTime: startTime,
    endTime: endTime,
  );
}

extension MemberParticipationRowMapper on MemberSegmentParticipationRow {
  MemberParticipation toDomain() => MemberParticipation(
    memberId: memberId,
    segmentId: segmentId,
    participating: participating,
  );
}

extension TeamRowMapper on TeamRow {
  Team toDomain() => Team(id: id, tripId: tripId, name: name);
}

extension TeamMemberRowMapper on TeamMemberRow {
  TeamMember toDomain() => TeamMember(teamId: teamId, memberId: memberId);
}
