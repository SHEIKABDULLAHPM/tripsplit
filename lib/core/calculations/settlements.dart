import 'dart:math' as math;

import '../../features/expenses/domain/expense.dart';
import '../../features/expenses/domain/expense_payment.dart';
import '../../features/expenses/domain/expense_share.dart';
import '../../features/settlements/domain/settlement.dart';
import 'balances.dart' show PaymentAllocator;

/// A single suggested transfer that resolves outstanding debt between two
/// members, in minor units.
class SettlementSuggestion {
  const SettlementSuggestion({
    required this.fromMemberId,
    required this.toMemberId,
    required this.minor,
  });

  final int fromMemberId;
  final int toMemberId;

  /// Amount that still needs to move from [fromMemberId] to [toMemberId].
  final int minor;
}

/// Result of settlement planning for a trip.
class SettlementResult {
  const SettlementResult({
    required this.suggestions,
    required this.remainingNets,
  });

  final List<SettlementSuggestion> suggestions;

  /// Net position per member AFTER recorded (paid) settlements are applied.
  final Map<int, int> remainingNets;

  /// Total outstanding debt still to be transferred across the group.
  int get totalOutstanding => suggestions.fold(0, (sum, s) => sum + s.minor);
}

/// Plans and grades settlements for a trip.
///
/// Settlements are transfers between members and never modify reported
/// spending or budget usage. Recorded, paid amounts are respected when
/// computing what still remains outstanding.
abstract final class SettlementCalculator {
  SettlementCalculator._();

  /// Grades a settlement from its recorded obligation and paid amounts.
  static SettlementStatus statusOf({
    required int amountMinor,
    required int amountPaidMinor,
  }) {
    if (amountPaidMinor >= amountMinor) {
      return SettlementStatus.paid;
    }
    if (amountPaidMinor <= 0) {
      return SettlementStatus.outstanding;
    }
    return SettlementStatus.partial;
  }

  /// Computes remaining nets and derives the settlement transfer plan.
  ///
  /// Without team-attributed payments the plan is the original greedy
  /// largest-debt-first matching over global member nets — the minimal set of
  /// transfers that clears every balance.
  ///
  /// When [teamMemberIds] is provided, the plan is resolved with team
  /// awareness: every non-payer participant's share is covered by the payers
  /// who funded their teams (split proportionally to how much each payer
  /// fronted, plus any generic payers), so a member only ever owes a payer of
  /// their own team. Remaining payer-vs-payer imbalances are then matched so
  /// every position closes exactly. This prevents cross-team contamination
  /// where a member from Team A could be mapped to a payer from Team B merely
  /// because their balances match.
  static SettlementResult calculate({
    required List<Expense> expenses,
    required List<ExpenseShare> shares,
    required List<Settlement> settlements,
    List<ExpensePayment> payments = const [],
    Map<int, Set<int>>? teamMemberIds,
  }) {
    final paymentsByExpense = PaymentAllocator.byExpense(payments);

    final hasTeamAllocations = payments.any((p) => p.teamId != null);

    if (!hasTeamAllocations || teamMemberIds == null || teamMemberIds.isEmpty) {
      return _calculateGreedy(
        expenses: expenses,
        shares: shares,
        settlements: settlements,
        payments: payments,
      );
    }

    final sharesByExpense = <int, List<ExpenseShare>>{};
    for (final share in shares) {
      sharesByExpense
          .putIfAbsent(share.expenseId, () => [])
          .add(share);
    }

    final memberToTeams = <int, Set<int>>{};
    for (final entry in teamMemberIds.entries) {
      for (final memberId in entry.value) {
        memberToTeams.putIfAbsent(memberId, () => {}).add(entry.key);
      }
    }

    final obligations = <_Obligation>[];

    for (final expense in expenses) {
      if (expense.externalAmountMinor < 0 ||
          expense.externalAmountMinor >= expense.amountMinor) {
        throw ArgumentError.value(
          expense,
          'expenses',
          'The external portion must be smaller than the expense amount so '
              'some of the expense is shared.',
        );
      }

      final expensePayments = paymentsByExpense[expense.id] ?? const [];
      final expenseShares = sharesByExpense[expense.id] ?? const [];

      if (expensePayments.length <= 1 || !_hasAllocationTeams(expensePayments)) {
        _allocateByGlobalNetting(
          expense: expense,
          payments: expensePayments,
          shares: expenseShares,
          obligations: obligations,
        );
      } else {
        _allocateMultiPayer(
          expense: expense,
          payments: expensePayments,
          shares: expenseShares,
          obligations: obligations,
          memberToTeams: memberToTeams,
        );
      }
    }

    final workingObligations = _applySettlements(
      obligations: obligations,
      settlements: settlements,
    );

    final remainingNets = _computeGlobalNets(
      expenses: expenses,
      shares: shares,
      settlements: settlements,
      payments: payments,
    );

    return _generateSuggestionsFromObligations(
      obligations: workingObligations,
      nets: remainingNets,
    );
  }

  /// Original greedy algorithm on global nets. Used when there are no team
  /// allocations.
  static SettlementResult _calculateGreedy({
    required List<Expense> expenses,
    required List<ExpenseShare> shares,
    required List<Settlement> settlements,
    required List<ExpensePayment> payments,
  }) {
    final nets = _computeGlobalNets(
      expenses: expenses,
      shares: shares,
      settlements: settlements,
      payments: payments,
    );

    final remainingNets = Map<int, int>.from(nets);

    final debtors = nets.entries.where((e) => e.value < 0).toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final creditors = nets.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final suggestions = <SettlementSuggestion>[];
    var di = 0;
    var ci = 0;
    while (di < debtors.length && ci < creditors.length) {
      final debt = -debtors[di].value;
      final credit = creditors[ci].value;
      final amount = math.min(debt, credit);
      if (amount > 0) {
        suggestions.add(SettlementSuggestion(
          fromMemberId: debtors[di].key,
          toMemberId: creditors[ci].key,
          minor: amount,
        ));
      }
      debtors[di] = MapEntry(debtors[di].key, debtors[di].value + amount);
      creditors[ci] = MapEntry(creditors[ci].key, creditors[ci].value - amount);
      if (debtors[di].value == 0) di++;
      if (creditors[ci].value == 0) ci++;
    }

    return SettlementResult(
      suggestions: suggestions,
      remainingNets: Map.unmodifiable(remainingNets),
    );
  }

  static Map<int, int> _computeGlobalNets({
    required List<Expense> expenses,
    required List<ExpenseShare> shares,
    required List<Settlement> settlements,
    required List<ExpensePayment> payments,
  }) {
    final nets = <int, int>{};
    final paymentsByExpense = PaymentAllocator.byExpense(payments);
    for (final expense in expenses) {
      final outlay = PaymentAllocator.groupOutlayByMember(
        expense,
        paymentsByExpense[expense.id] ?? const [],
      );
      for (final entry in outlay.entries) {
        nets[entry.key] = (nets[entry.key] ?? 0) + entry.value;
      }
    }
    for (final share in shares) {
      nets[share.memberId] =
          (nets[share.memberId] ?? 0) - share.shareMinor;
    }
    for (final settlement in settlements) {
      final paid = settlement.amountPaidMinor;
      if (paid <= 0) continue;
      nets[settlement.fromMemberId] =
          (nets[settlement.fromMemberId] ?? 0) + paid;
      nets[settlement.toMemberId] =
          (nets[settlement.toMemberId] ?? 0) - paid;
    }
    return nets;
  }

  /// Allocates an expense using global netting: for each member, outlay minus
  /// share is their net position. Members with negative net owe members with
  /// positive net.
  static void _allocateByGlobalNetting({
    required Expense expense,
    required List<ExpensePayment> payments,
    required List<ExpenseShare> shares,
    required List<_Obligation> obligations,
  }) {
    final outlay = PaymentAllocator.groupOutlayByMember(expense, payments);

    // Build per-member net: outlay minus share
    final nets = <int, int>{};
    for (final entry in outlay.entries) {
      nets[entry.key] = (nets[entry.key] ?? 0) + entry.value;
    }
    for (final share in shares) {
      nets[share.memberId] = (nets[share.memberId] ?? 0) - share.shareMinor;
    }

    // Split into debtors (negative net) and creditors (positive net)
    final debtors = nets.entries.where((e) => e.value < 0).toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final creditors = nets.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Match debtors with creditors
    var di = 0;
    var ci = 0;
    while (di < debtors.length && ci < creditors.length) {
      final debt = -debtors[di].value;
      final credit = creditors[ci].value;
      final amount = math.min(debt, credit);
      if (amount > 0) {
        obligations.add(_Obligation(
          fromMemberId: debtors[di].key,
          toMemberId: creditors[ci].key,
          amountMinor: amount,
          expenseId: expense.id,
        ));
      }
      // Decrement nets
      debtors[di] = MapEntry(debtors[di].key, debtors[di].value + amount);
      creditors[ci] = MapEntry(creditors[ci].key, creditors[ci].value - amount);
      if (debtors[di].value == 0) di++;
      if (creditors[ci].value == 0) ci++;
    }
  }

  /// Allocates a multi-payer expense with team awareness.
  ///
  /// Obligations are created in two layers:
  /// 1. Each non-payer participant's share is covered by the payers of the
  ///    teams the participant belongs to (plus any generic payers, and falling
  ///    back to every payer when the participant has no team with a payer),
  ///    split proportionally to how much each payer fronted. A payer's own
  ///    share is always self-covered and never becomes an obligation.
  /// 2. The payers' remaining imbalances (what each payer still needs to
  ///    receive or still overpaid after their team's shares are mapped) are
  ///    matched among themselves so the expense's positions close exactly.
  static void _allocateMultiPayer({
    required Expense expense,
    required List<ExpensePayment> payments,
    required List<ExpenseShare> shares,
    required List<_Obligation> obligations,
    required Map<int, Set<int>> memberToTeams,
  }) {
    final payers = <({int memberId, int? teamId, int paidAmount})>[];
    for (final payment in payments) {
      if (payment.amountMinor <= 0) continue;
      payers.add((
        memberId: payment.memberId,
        teamId: payment.teamId,
        paidAmount: payment.amountMinor,
      ));
    }
    if (payers.isEmpty) return;

    final payerIds = payers.map((p) => p.memberId).toSet();
    final teamPayers = <int, List<({int memberId, int paidAmount})>>{};
    final genericPayers = <({int memberId, int paidAmount})>[];
    for (final payer in payers) {
      final entry = (memberId: payer.memberId, paidAmount: payer.paidAmount);
      final teamId = payer.teamId;
      if (teamId == null) {
        genericPayers.add(entry);
      } else {
        teamPayers.putIfAbsent(teamId, () => []).add(entry);
      }
    }

    final layerOne = <_Obligation>[];

    // Layer 1: cover every non-payer participant's share.
    for (final share in shares) {
      if (share.shareMinor <= 0) continue;
      if (payerIds.contains(share.memberId)) continue;

      final membersTeams = memberToTeams[share.memberId] ?? const <int>{};
      final sameTeamCoverers = <({int memberId, int paidAmount})>[];
      for (final teamId in membersTeams) {
        sameTeamCoverers.addAll(teamPayers[teamId] ?? const []);
      }
      final candidates = sameTeamCoverers.isNotEmpty
          ? [...sameTeamCoverers, ...genericPayers]
          : payers
              .map((p) => (
                memberId: p.memberId,
                paidAmount: p.paidAmount,
              ))
              .toList();
      // Merge duplicate entries for the same payer (a payer may fund several
      // of the participant's teams, or join in via both a team and a generic
      // payment); their total outlay is the correct cover weight.
      final mergedCoverers = <int, int>{};
      for (final coverer in candidates) {
        mergedCoverers[coverer.memberId] =
            (mergedCoverers[coverer.memberId] ?? 0) + coverer.paidAmount;
      }
      if (mergedCoverers.isEmpty) continue;

      _distributeShare(
        fromMemberId: share.memberId,
        amountMinor: share.shareMinor,
        coverers: [
          for (final entry in mergedCoverers.entries)
            (memberId: entry.key, paidAmount: entry.value),
        ],
        expenseId: expense.id,
        obligations: layerOne,
      );
    }

    // Layer 2: close each payer's position. A payer's net is what they fronted
    // for the expense minus their own share, reduced by the obligations their
    // team's non-payer members already owe them.
    final nets = <int, int>{};
    for (final payer in payers) {
      nets[payer.memberId] = (nets[payer.memberId] ?? 0) + payer.paidAmount;
    }
    final shareAmounts = <int, int>{};
    for (final share in shares) {
      shareAmounts[share.memberId] = share.shareMinor;
    }
    for (final payer in payers) {
      nets[payer.memberId] =
          (nets[payer.memberId] ?? 0) - (shareAmounts[payer.memberId] ?? 0);
    }
    for (final obligation in layerOne) {
      nets[obligation.toMemberId] =
          (nets[obligation.toMemberId] ?? 0) - obligation.amountMinor;
    }

    _matchResidualNets(
      nets: nets,
      expenseId: expense.id,
      obligations: obligations,
    );

    obligations.addAll(layerOne);
  }

  /// Splits [amountMinor] across [coverers] proportionally to how much each
  /// coverer paid, rounding with largest remainders so the parts always sum to
  /// exactly [amountMinor]. The same input always yields the same split.
  static void _distributeShare({
    required int fromMemberId,
    required int amountMinor,
    required List<({int memberId, int paidAmount})> coverers,
    required int expenseId,
    required List<_Obligation> obligations,
  }) {
    final working = <({int memberId, int paidAmount})>[
      ...coverers,
    ]..sort((a, b) => a.memberId.compareTo(b.memberId));
    final totalPaid = working.fold<int>(0, (sum, c) => sum + c.paidAmount);
    if (totalPaid <= 0) return;

    var assigned = 0;
    final amounts = <int>[];
    for (final coverer in working) {
      final amount = (amountMinor * coverer.paidAmount) ~/ totalPaid;
      amounts.add(amount);
      assigned += amount;
    }
    // Hand the rounding remainder to the first coverers, one minor unit each.
    for (var i = 0; i < working.length && assigned < amountMinor; i++) {
      amounts[i] += 1;
      assigned += 1;
    }

    for (var i = 0; i < working.length; i++) {
      if (amounts[i] <= 0) continue;
      obligations.add(_Obligation(
        fromMemberId: fromMemberId,
        toMemberId: working[i].memberId,
        amountMinor: amounts[i],
        expenseId: expenseId,
      ));
    }
  }

  /// Matches the remaining payer imbalances: payers that under-received owe the
  /// payers that still over-received, largest amounts first and deterministically.
  static void _matchResidualNets({
    required Map<int, int> nets,
    required int expenseId,
    required List<_Obligation> obligations,
  }) {
    final overpaid = nets.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) {
        final byValue = b.value.compareTo(a.value);
        return byValue != 0 ? byValue : a.key.compareTo(b.key);
      });
    final underpaid = nets.entries
        .where((e) => e.value < 0)
        .map((e) => MapEntry(e.key, -e.value))
        .toList()
      ..sort((a, b) {
        final byValue = b.value.compareTo(a.value);
        return byValue != 0 ? byValue : a.key.compareTo(b.key);
      });

    var oi = 0;
    var ui = 0;
    while (oi < overpaid.length && ui < underpaid.length) {
      final excess = overpaid[oi].value;
      final deficit = underpaid[ui].value;
      final amount = math.min(excess, deficit);
      if (amount > 0) {
        obligations.add(_Obligation(
          fromMemberId: underpaid[ui].key,
          toMemberId: overpaid[oi].key,
          amountMinor: amount,
          expenseId: expenseId,
        ));
      }
      overpaid[oi] = MapEntry(overpaid[oi].key, excess - amount);
      underpaid[ui] = MapEntry(underpaid[ui].key, deficit - amount);
      if (overpaid[oi].value == 0) oi++;
      if (underpaid[ui].value == 0) ui++;
    }
  }

  /// Applies recorded settlements to reduce outstanding obligations.
  ///
  /// A payment first reduces the debtor's obligation to the exact creditor it
  /// was raised for, then — if the payment exceeds that single edge (e.g. an
  /// older cross-team settlement that no longer matches the team-aware
  /// structure) — any remaining debt of the same member. This keeps recorded
  /// cash always effective: what a member has already paid out can never be
  /// re-charged, regardless of how the debt was later re-mapped.
  static List<_Obligation> _applySettlements({
    required List<_Obligation> obligations,
    required List<Settlement> settlements,
  }) {
    final working = List<_Obligation>.of(obligations);

    for (final settlement in settlements) {
      if (settlement.amountPaidMinor <= 0) continue;

      var remaining = settlement.amountPaidMinor;

      // First reduce this debtor's obligation to this exact creditor.
      for (var i = 0; i < working.length && remaining > 0; i++) {
        final obligation = working[i];
        if (obligation.fromMemberId == settlement.fromMemberId &&
            obligation.toMemberId == settlement.toMemberId) {
          final reduction = math.min(remaining, obligation.amountMinor);
          working[i] = _Obligation(
            fromMemberId: obligation.fromMemberId,
            toMemberId: obligation.toMemberId,
            amountMinor: obligation.amountMinor - reduction,
            expenseId: obligation.expenseId,
          );
          remaining -= reduction;
        }
      }

      // Then reduce any remaining debt of the same member so the paid cash is
      // never lost from the plan.
      for (var i = 0; i < working.length && remaining > 0; i++) {
        final obligation = working[i];
        if (obligation.fromMemberId == settlement.fromMemberId) {
          final reduction = math.min(remaining, obligation.amountMinor);
          working[i] = _Obligation(
            fromMemberId: obligation.fromMemberId,
            toMemberId: obligation.toMemberId,
            amountMinor: obligation.amountMinor - reduction,
            expenseId: obligation.expenseId,
          );
          remaining -= reduction;
        }
      }
    }

    return working.where((o) => o.amountMinor > 0).toList();
  }

  /// Generates settlement suggestions from the team-aware obligation graph.
  ///
  /// Obligations that point in opposite directions between the same pair are
  /// netted into a single transfer. Emission is fully deterministic: edges are
  /// ordered by payer, then recipient. The [nets] map is preserved verbatim as
  /// the post-settlement member net positions.
  static SettlementResult _generateSuggestionsFromObligations({
    required List<_Obligation> obligations,
    required Map<int, int> nets,
  }) {
    // Group obligations by (from, to) pair and net opposing ones out.
    final netObligations = <(int, int), int>{};
    for (final obligation in obligations) {
      if (obligation.amountMinor <= 0) continue;
      final key = (obligation.fromMemberId, obligation.toMemberId);
      final reverseKey = (obligation.toMemberId, obligation.fromMemberId);
      final direct = netObligations[key] ?? 0;
      final reverse = netObligations[reverseKey] ?? 0;
      if (reverse > 0) {
        // A reverse obligation exists; cancel against this one.
        final net = obligation.amountMinor - reverse;
        if (net > 0) {
          netObligations[key] = direct + net;
          netObligations.remove(reverseKey);
        } else if (net < 0) {
          netObligations[reverseKey] = -net;
        } else {
          netObligations.remove(key);
          netObligations.remove(reverseKey);
        }
      } else {
        netObligations[key] = direct + obligation.amountMinor;
      }
    }

    final orderedPairs = netObligations.keys.toList()
      ..sort((a, b) {
        final byFrom = a.$1.compareTo(b.$1);
        return byFrom != 0 ? byFrom : a.$2.compareTo(b.$2);
      });

    return SettlementResult(
      suggestions: [
        for (final pair in orderedPairs)
          SettlementSuggestion(
            fromMemberId: pair.$1,
            toMemberId: pair.$2,
            minor: netObligations[pair]!,
          ),
      ],
      remainingNets: Map.unmodifiable(nets),
    );
  }

  /// The amount still outstanding between a specific pair, derived from the
  /// planned [suggestions] (which already account for recorded payments).
  static int outstandingBetween(
    List<SettlementSuggestion> suggestions, {
    required int fromMemberId,
    required int toMemberId,
  }) => suggestions
      .where(
        (s) => s.fromMemberId == fromMemberId && s.toMemberId == toMemberId,
      )
      .fold<int>(0, (sum, s) => sum + s.minor);

  /// Total cash actually transferred between a pair across every recorded
  /// settlement row. Recorded payments are the "already handled" truth; they
  /// only ever reduce what the planned suggestions still require.
  static int totalPaidBetween(
    List<Settlement> settlements, {
    required int fromMemberId,
    required int toMemberId,
  }) => settlements
      .where(
        (s) => s.fromMemberId == fromMemberId && s.toMemberId == toMemberId,
      )
      .fold<int>(0, (sum, s) => sum + s.amountPaidMinor);

  /// The live, up-to-date obligation for a pair in the current plan.
  ///
  /// This is the single source of truth for what is still owed: the already
  /// transferred cash plus whatever the latest suggestions still require. It
  /// stays correct even when expenses are added, edited or deleted after a
  /// settlement was recorded (unlike stored row obligations, which only ever
  /// reflect the debt at the moment the row was written).
  static int liveObligationBetween(
    List<Settlement> settlements,
    List<SettlementSuggestion> suggestions, {
    required int fromMemberId,
    required int toMemberId,
  }) =>
      totalPaidBetween(
        settlements,
        fromMemberId: fromMemberId,
        toMemberId: toMemberId,
      ) +
      outstandingBetween(
        suggestions,
        fromMemberId: fromMemberId,
        toMemberId: toMemberId,
      );

  /// Checks if any payment has a team allocation.
  static bool _hasAllocationTeams(List<ExpensePayment> payments) =>
      payments.any((p) => p.teamId != null);
}

/// Internal representation of a financial obligation between two members.
class _Obligation {
  const _Obligation({
    required this.fromMemberId,
    required this.toMemberId,
    required this.amountMinor,
    required this.expenseId,
  });

  final int fromMemberId;
  final int toMemberId;
  final int amountMinor;
  final int expenseId;
}
