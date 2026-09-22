import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/calculations/expense_split.dart';
import '../../../core/calculations/money.dart';
import '../../../core/calculations/participation.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/app_money_field.dart';
import '../../../core/widgets/app_section_header.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/member_avatar.dart';
import '../../../core/widgets/money_text.dart';
import '../../../injection/database_providers.dart';
import '../../expenses/domain/expense_payment.dart';
import '../../expenses/domain/expense_scope.dart';
import '../../journey/domain/journey.dart';
import '../../members/domain/member.dart';
import '../../trips/data/trip_views.dart';

class _OtherPayer {
  _OtherPayer({required this.memberId, required this.controller});
  int memberId;
  final TextEditingController controller;
}

class ExpenseFormScreen extends ConsumerStatefulWidget {
  const ExpenseFormScreen._({
    required this.tripId,
    required this.editExpenseId,
    this.initialSegmentId,
    this.initialTeamId,
    this.initialPayerId,
  });

  factory ExpenseFormScreen.create({
    required int tripId,
    int? initialSegmentId,
    int? initialTeamId,
    int? initialPayerId,
  }) => ExpenseFormScreen._(
    tripId: tripId,
    editExpenseId: null,
    initialSegmentId: initialSegmentId,
    initialTeamId: initialTeamId,
    initialPayerId: initialPayerId,
  );

  factory ExpenseFormScreen.edit({
    required int tripId,
    required int expenseId,
  }) => ExpenseFormScreen._(tripId: tripId, editExpenseId: expenseId);

  final int tripId;
  final int? editExpenseId;
  final int? initialSegmentId;
  final int? initialTeamId;
  final int? initialPayerId;

  bool get isEditing => editExpenseId != null;

  @override
  ConsumerState<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends ConsumerState<ExpenseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  final _externalController = TextEditingController();
  final _categoryController = TextEditingController();
  int? _payerMemberId;
  final Set<int> _participants = {};
  final Map<int, int> _customShares = {};
  ExpenseScope _scope = ExpenseScope.shared;
  int? _segmentId;
  final List<int> _teamIds = [];
  final Map<int, int> _teamPayerIds = {};
  final Map<int, TextEditingController> _teamPaidControllers = {};
  final List<_OtherPayer> _otherPayers = [];
  bool _saving = false;
  bool _initializedDefaults = false;
  String? _category;
  DateTime? _spentAt;

  @override
  void initState() {
    super.initState();
    if (widget.isEditing) {
      _loadExisting();
    } else {
      _spentAt = DateTime.now();
      _applyInitialContext();
    }
  }

  void _applyInitialContext() {
    if (widget.initialPayerId != null) _payerMemberId = widget.initialPayerId;
    if (widget.initialSegmentId != null) {
      _segmentId = widget.initialSegmentId;
      _scope = ExpenseScope.segment;
    } else if (widget.initialTeamId != null) {
      _teamIds.add(widget.initialTeamId!);
      _scope = ExpenseScope.team;
    }
  }

  Future<void> _loadExisting() async {
    final tripView = await ref.read(tripViewProvider(widget.tripId).future);
    if (tripView == null) return;
    final matches = tripView.expenses
        .map((item) => item.expense)
        .where((e) => e.id == widget.editExpenseId);
    if (matches.isEmpty) return;
    final expense = matches.first;
    final shares = tripView.expenses
        .firstWhere(
          (item) => item.expense.id == widget.editExpenseId,
          orElse: () => tripView.expenses.first,
        )
        .shares;

    _descriptionController.text = expense.description;
    _amountController.text = MoneyCalculator.formatNoSymbol(
      expense.amountMinor,
    );
    if (expense.externalAmountMinor > 0) {
      _externalController.text = MoneyCalculator.formatNoSymbol(
        expense.externalAmountMinor,
      );
    }
    _payerMemberId = expense.payerMemberId;
    _scope = expense.scope;
    _segmentId = expense.segmentId;
    _teamIds
      ..clear()
      ..addAll(
        expense.teamIds.isEmpty && expense.teamId != null
            ? [expense.teamId!]
            : expense.teamIds,
      );
    _category = expense.category;
    _spentAt = expense.spentAt;
    if (_category != null) _categoryController.text = _category!;
    _participants
      ..clear()
      ..addAll(shares.map((s) => s.memberId));
    if (expense.scope == ExpenseScope.custom) {
      _customShares.clear();
      for (final s in shares) {
        _customShares[s.memberId] = s.shareMinor;
      }
    }

    final payments = tripView.payments
        .where((p) => p.expenseId == expense.id)
        .toList();
    final totalPaid = payments.fold<int>(0, (sum, p) => sum + p.amountMinor);
    if (totalPaid == expense.amountMinor) {
      for (final payment in payments) {
        final teamId = payment.teamId;
        if (teamId != null) {
          _teamPayerIds[teamId] = payment.memberId;
          _teamPaidControllers.putIfAbsent(
            teamId,
            () => TextEditingController(
              text: MoneyCalculator.formatNoSymbol(payment.amountMinor),
            ),
          );
        } else if (payment.memberId != expense.payerMemberId) {
          _otherPayers.add(
            _OtherPayer(
              memberId: payment.memberId,
              controller: TextEditingController(
                text: MoneyCalculator.formatNoSymbol(payment.amountMinor),
              ),
            ),
          );
        }
      }
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    _externalController.dispose();
    _categoryController.dispose();
    for (final p in _otherPayers) {
      p.controller.dispose();
    }
    for (final controller in _teamPaidControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  int? get _amountMinor =>
      MoneyCalculator.parseToMinorOrNull(_amountController.text);
  int? get _externalMinor =>
      MoneyCalculator.parseToMinorOrNull(_externalController.text);
  int? get _groupAmountMinor {
    final amount = _amountMinor;
    if (amount == null) return null;
    return amount - (_externalMinor ?? 0);
  }

  bool get _customSharesValid {
    if (_scope != ExpenseScope.custom) return true;
    final total = _groupAmountMinor;
    if (total == null || total <= 0) return true;
    final allocated = _customShares.values.fold<int>(0, (s, v) => s + v);
    return allocated == total;
  }

  void _selectScope(
    ExpenseScope scope, {
    required List<Member> members,
    required JourneyView? journey,
  }) {
    setState(() => _scope = scope);
    if (scope == ExpenseScope.team) {
      _applyTeamDefaults(members: members);
      return;
    }
    _applyScopeDefaults(members: members, journey: journey);
  }

  Future<void> _applyTeamDefaults({required List<Member> members}) async {
    final ids = List<int>.of(_teamIds);
    if (ids.isEmpty) {
      setState(_participants.clear);
      return;
    }
    final memberIds = <int>{};
    for (final id in ids) {
      final teamMembers = await ref
          .read(teamRepositoryProvider)
          .getTeamMembers(id);
      for (final member in teamMembers) {
        memberIds.add(member.id);
      }
    }
    if (!mounted) return;
    setState(
      () => _participants
        ..clear()
        ..addAll(memberIds),
    );
  }

  void _applyScopeDefaults({
    required List<Member> members,
    required JourneyView? journey,
  }) {
    setState(() {
      _participants.clear();
      switch (_scope) {
        case ExpenseScope.individual:
          if (_payerMemberId != null) _participants.add(_payerMemberId!);
          break;
        case ExpenseScope.shared:
          _participants.addAll(members.map((m) => m.id));
          break;
        case ExpenseScope.team:
          break;
        case ExpenseScope.segment:
          final seg = journey?.segments
              .where((s) => s.id == _segmentId)
              .toList();
          if (seg != null && seg.isNotEmpty && journey != null) {
            final order = _segmentOrder(journey.segments, seg.first.id);
            _participants.addAll(
              ParticipationCalculator.participatingMemberIds(
                segment: seg.first,
                segmentOrder: order,
                members: members,
                segments: journey.segments,
                locations: journey.locations,
                participations: journey.participations,
              ),
            );
          }
          break;
        case ExpenseScope.custom:
          _customShares.clear();
          for (final m in members) {
            _customShares[m.id] = 0;
          }
          break;
      }
    });
  }

  void _applyScopeDefaultsDirect({
    required List<Member> members,
    required JourneyView? journey,
  }) {
    _participants.clear();
    switch (_scope) {
      case ExpenseScope.individual:
        if (_payerMemberId != null) _participants.add(_payerMemberId!);
        break;
      case ExpenseScope.shared:
        _participants.addAll(members.map((m) => m.id));
        break;
      case ExpenseScope.team:
        break;
      case ExpenseScope.segment:
        final seg = journey?.segments.where((s) => s.id == _segmentId).toList();
        if (seg != null && seg.isNotEmpty && journey != null) {
          final order = _segmentOrder(journey.segments, seg.first.id);
          _participants.addAll(
            ParticipationCalculator.participatingMemberIds(
              segment: seg.first,
              segmentOrder: order,
              members: members,
              segments: journey.segments,
              locations: journey.locations,
              participations: journey.participations,
            ),
          );
        }
        break;
      case ExpenseScope.custom:
        _customShares.clear();
        for (final m in members) {
          _customShares[m.id] = 0;
        }
        break;
    }
  }

  Future<void> _applyTeamDefaultsDirect({required List<Member> members}) async {
    await _applyTeamDefaults(members: members);
  }

  void _toggleTeam(int teamId, {required List<Member> members}) {
    setState(() {
      if (_teamIds.contains(teamId)) {
        _teamIds.remove(teamId);
      } else {
        _teamIds.add(teamId);
      }
      _pruneTeamPayers();
    });
    _applyTeamDefaults(members: members);
  }

  void _pruneTeamPayers() {
    final selected = _teamIds.toSet();
    final stale = _teamPayerIds.keys
        .where((id) => !selected.contains(id))
        .toList();
    for (final id in stale) {
      _teamPayerIds.remove(id);
      _teamPaidControllers.remove(id)?.dispose();
    }
  }

  /// Per-team payer rows: a team may skip paying entirely (covered by another
  /// team), so rows are built only for teams that designate a payer with a
  /// positive amount.
  List<({int teamId, int memberId, int amountMinor})> _teamPaymentRows() {
    final rows = <({int teamId, int memberId, int amountMinor})>[];
    for (final teamId in _teamIds) {
      final payer = _teamPayerIds[teamId];
      final controller = _teamPaidControllers[teamId];
      if (payer == null || controller == null) continue;
      final amount = MoneyCalculator.parseToMinorOrNull(controller.text);
      if (amount == null || amount <= 0) continue;
      rows.add((teamId: teamId, memberId: payer, amountMinor: amount));
    }
    return rows;
  }

  int get _teamPaymentsTotal =>
      _teamPaymentRows().fold<int>(0, (sum, row) => sum + row.amountMinor);

  int get _otherPayersTotal => _otherPayers.fold<int>(
    0,
    (sum, p) =>
        sum + (MoneyCalculator.parseToMinorOrNull(p.controller.text) ?? 0),
  );

  static int _segmentOrder(List<TravelSegment> segments, int segmentId) {
    final sorted = [...segments]
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    return sorted.indexWhere((s) => s.id == segmentId);
  }

  /// All participants across all selected teams, for cross-team payer
  /// selection. This allows a member from any selected team to pay on behalf
  /// of any other selected team.
  List<Member> _allParticipantsForTeams(
    List<Team> allTeams,
    List<Member> allMembers,
  ) {
    final memberIds = <int>{};
    for (final teamId in _teamIds) {
      final teamMembers = ref.watch(teamMembersProvider(teamId)).value;
      if (teamMembers != null) {
        for (final member in teamMembers) {
          memberIds.add(member.id);
        }
      }
    }
    return allMembers.where((m) => memberIds.contains(m.id)).toList();
  }

  /// Fetches all members of the currently selected teams for the participant
  /// selector. When scope is team, only team members should be shown.
  Future<List<Member>> _fetchTeamMembers() async {
    final memberIds = <int>{};
    for (final teamId in _teamIds) {
      final teamMembers = await ref
          .read(teamRepositoryProvider)
          .getTeamMembers(teamId);
      for (final member in teamMembers) {
        memberIds.add(member.id);
      }
    }
    final tripView = ref.read(tripViewProvider(widget.tripId)).value;
    if (tripView == null) return const [];
    return tripView.members.where((m) => memberIds.contains(m.id)).toList();
  }

  Future<void> _submit({required List<Member> members}) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final amountMinor = MoneyCalculator.parseToMinor(
      _amountController.text,
      label: 'Amount',
    );
    final externalMinor = _externalController.text.trim().isEmpty
        ? 0
        : MoneyCalculator.parseToMinor(
            _externalController.text,
            label: 'External portion',
          );

    var payerMemberId = _payerMemberId ?? members.first.id;
    int? payerTeamId;
    var otherPayers = <ExpensePayment>[
      for (final p in _otherPayers)
        if (p.controller.text.trim().isNotEmpty)
          ExpensePayment(
            id: 0,
            expenseId: 0,
            memberId: p.memberId,
            amountMinor:
                MoneyCalculator.parseToMinorOrNull(p.controller.text) ?? 0,
          ),
    ];

    if (_scope == ExpenseScope.team) {
      // Team payment rows determine who paid for which team.
      // Individual otherPayers (from "Other people who paid") are independent
      // and represent additional payments on top of team-level payments.
      final rows = _teamPaymentRows();
      if (rows.isEmpty && otherPayers.isEmpty) {
        _showMessage(
          'Choose a payer for at least one team, or add other payers.',
        );
        return;
      }
      if (rows.isNotEmpty) {
        final primaryRow = rows.firstWhere(
          (row) => row.memberId == _payerMemberId,
          orElse: () => rows.first,
        );
        payerMemberId = primaryRow.memberId;
        payerTeamId = primaryRow.teamId;
        // Convert other team rows (non-primary) into otherPayers.
        final teamOtherPayers = [
          for (final row in rows)
            if (row.teamId != primaryRow.teamId)
              ExpensePayment(
                id: 0,
                expenseId: 0,
                memberId: row.memberId,
                amountMinor: row.amountMinor,
                teamId: row.teamId,
              ),
        ];
        // Merge: team other-payers + individual other-payers.
        otherPayers = [...teamOtherPayers, ...otherPayers];
      }
    }

    setState(() => _saving = true);
    try {
      final repo = ref.read(expenseRepositoryProvider);
      final cat = _category?.trim().isEmpty == true ? null : _category?.trim();
      final customShares = _scope == ExpenseScope.custom
          ? {for (final id in _participants) id: _customShares[id] ?? 0}
          : const <int, int>{};
      final legacyTeamId = _teamIds.isNotEmpty ? _teamIds.first : null;
      if (widget.isEditing) {
        await repo.updateExpense(
          expenseId: widget.editExpenseId!,
          description: _descriptionController.text.trim(),
          amountMinor: amountMinor,
          externalAmountMinor: externalMinor,
          payerMemberId: payerMemberId,
          scope: _scope,
          segmentId: _segmentId,
          teamId: legacyTeamId,
          teamIds: List.of(_teamIds),
          payerTeamId: payerTeamId,
          category: cat,
          spentAt: _spentAt,
          participantMemberIds: _participants.toList(),
          otherPayers: otherPayers,
          customShares: customShares,
        );
      } else {
        await repo.createExpense(
          tripId: widget.tripId,
          description: _descriptionController.text.trim(),
          amountMinor: amountMinor,
          externalAmountMinor: externalMinor,
          payerMemberId: payerMemberId,
          scope: _scope,
          segmentId: _segmentId,
          teamId: legacyTeamId,
          teamIds: List.of(_teamIds),
          payerTeamId: payerTeamId,
          category: cat,
          spentAt: _spentAt,
          participantMemberIds: _participants.toList(),
          otherPayers: otherPayers,
          customShares: customShares,
        );
      }
      if (mounted) context.pop();
    } on AppException catch (e) {
      if (mounted) _showMessage(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(tripViewProvider(widget.tripId));
    final journey = ref.watch(journeyViewProvider(widget.tripId));
    final teams = ref.watch(teamsForTripProvider(widget.tripId));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit expense' : 'New expense'),
      ),
      body: SafeArea(
        bottom: true,
        child: AsyncValueView<TripView?>(
          value: view,
          onRetry: () => ref.invalidate(tripViewProvider(widget.tripId)),
          isEmpty: (value) => value == null || value.members.isEmpty,
          empty: const Center(
            child: Text('Add members before recording expenses.'),
          ),
          builder: (tripView) {
            if (tripView == null) return const SizedBox.shrink();
            final members = tripView.members;
            final journeyValue = journey.value;
            if (_payerMemberId == null && members.isNotEmpty) {
              _payerMemberId = members.first.id;
            }

            if (!_initializedDefaults) {
              _initializedDefaults = true;
              if (_participants.isEmpty) {
                if (_scope == ExpenseScope.segment && _segmentId != null) {
                  _applyScopeDefaultsDirect(
                    members: members,
                    journey: journeyValue,
                  );
                } else if (_scope == ExpenseScope.team && _teamIds.isNotEmpty) {
                  _applyTeamDefaultsDirect(members: members);
                } else if (_scope == ExpenseScope.individual &&
                    _payerMemberId != null) {
                  _participants.add(_payerMemberId!);
                } else if (_scope != ExpenseScope.custom) {
                  _participants.addAll(members.map((m) => m.id));
                }
              }
            }

            return Form(
              key: _formKey,
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.lg,
                  AppSpacing.xl,
                  AppSpacing.xxl,
                ),
                children: [
                  const SectionHeader('Expense details'),
                  TextFormField(
                    controller: _descriptionController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'What was purchased',
                      hintText: 'e.g. Train tickets',
                    ),
                    maxLength: 200,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Enter a name' : null,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppMoneyField(
                    controller: _amountController,
                    label: 'Amount',
                    hintText: 'e.g. 1200',
                    constraint: AppMoneyConstraint.requiredPositive,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppMoneyField(
                    controller: _externalController,
                    label: 'External portion (not shared)',
                    hintText: 'Optional',
                    constraint: AppMoneyConstraint.optionalNonNegative,
                    maxMinor: _amountMinor,
                    maxStrict: true,
                    maxExceededMessage:
                        'Must be smaller than the amount so some of the expense is shared.',
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (_scope != ExpenseScope.team) ...[
                    const SectionHeader('Paid by'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final member in members)
                          ChoiceChip(
                            label: Text(member.name),
                            selected: _payerMemberId == member.id,
                            onSelected: (sel) => setState(() {
                              if (sel) _payerMemberId = member.id;
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  const SectionHeader('Split between'),
                  if (_scope == ExpenseScope.team) ...[
                    FutureBuilder<List<Member>>(
                      future: _fetchTeamMembers(),
                      builder: (context, snapshot) {
                        final teamMembers = snapshot.data ?? const [];
                        return Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            for (final member in teamMembers)
                              FilterChip(
                                label: Text(member.name),
                                selected: _participants.contains(member.id),
                                onSelected: (sel) => setState(() {
                                  if (sel) {
                                    _participants.add(member.id);
                                  } else if (_payerMemberId != member.id) {
                                    _participants.remove(member.id);
                                  }
                                }),
                              ),
                            if (teamMembers.isEmpty)
                              Text(
                                'Select a team to see its members',
                                style: Theme.of(context).textTheme.bodyMuted,
                              ),
                          ],
                        );
                      },
                    ),
                  ] else ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final member in members)
                          FilterChip(
                            label: Text(member.name),
                            selected: _participants.contains(member.id),
                            onSelected: (sel) => setState(() {
                              if (sel) {
                                _participants.add(member.id);
                              } else if (_payerMemberId != member.id) {
                                _participants.remove(member.id);
                              }
                            }),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  const SectionHeader('Applies to'),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (final entry in const [
                          (
                            ExpenseScope.individual,
                            'Individual',
                            'Only the payer',
                            Icons.person_outline,
                          ),
                          (
                            ExpenseScope.shared,
                            'Shared',
                            'Split between all members',
                            Icons.people_outline,
                          ),
                          (
                            ExpenseScope.team,
                            'Team',
                            'Split within team members',
                            Icons.groups_outlined,
                          ),
                          (
                            ExpenseScope.segment,
                            'Segment',
                            'Only during a travel segment',
                            Icons.route_outlined,
                          ),
                          (
                            ExpenseScope.custom,
                            'Custom',
                            'Set custom shares per member',
                            Icons.tune,
                          ),
                        ])
                          _ScopeOption(
                            scope: entry.$1,
                            label: entry.$2,
                            description: entry.$3,
                            icon: entry.$4,
                            selected: _scope == entry.$1,
                            onTap: () => _selectScope(
                              entry.$1,
                              members: members,
                              journey: journeyValue,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_scope == ExpenseScope.custom) ...[
                    const SizedBox(height: 8),
                    _CustomShareInputs(
                      participants: members
                          .where((m) => _participants.contains(m.id))
                          .toList(),
                      customShares: _customShares,
                      groupAmountMinor: _groupAmountMinor,
                      onChanged: (shares) =>
                          setState(() => _customShares.addAll(shares)),
                    ),
                  ],
                  if (_scope == ExpenseScope.team) ...[
                    const SizedBox(height: 8),
                    _TeamMultiPicker(
                      teams: teams.value ?? const [],
                      selectedIds: _teamIds,
                      onToggle: (id) => _toggleTeam(id, members: members),
                    ),
                    if (_teamIds.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Who paid, per team',
                        style: Theme.of(context).textTheme.sectionTitle,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Pick a payer from each team and how much that team paid. '
                        'A team without a payer is covered by the others.',
                        style: Theme.of(context).textTheme.captionMuted,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      for (final teamId in _teamIds) ...[
                        _TeamPayerRow(
                          team:
                              teams.value?.firstWhere(
                                (t) => t.id == teamId,
                                orElse: () => Team(
                                  id: teamId,
                                  tripId: 0,
                                  name: 'Team $teamId',
                                ),
                              ) ??
                              Team(id: teamId, tripId: 0, name: 'Team $teamId'),
                          members: _allParticipantsForTeams(
                            teams.value ?? const [],
                            members,
                          ),
                          payerId: _teamPayerIds[teamId],
                          amountController: _teamPaidControllers[teamId],
                          onPayerChanged: (memberId) => setState(() {
                            if (memberId <= 0) {
                              _teamPayerIds.remove(teamId);
                            } else {
                              _teamPayerIds[teamId] = memberId;
                              _teamPaidControllers.putIfAbsent(
                                teamId,
                                TextEditingController.new,
                              );
                            }
                          }),
                          onAmountChanged: () => setState(() {}),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      Builder(
                        builder: (context) {
                          final amount = _amountMinor;
                          if (amount == null || amount <= 0) {
                            return const SizedBox.shrink();
                          }
                          final total = _teamPaymentsTotal;
                          final matched = total == amount;
                          final remaining = amount - total;
                          return Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(AppSpacing.md),
                            decoration: BoxDecoration(
                              color: matched
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer.withAlpha(80)
                                  : Theme.of(
                                      context,
                                    ).colorScheme.errorContainer.withAlpha(80),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      matched
                                          ? Icons.check_circle_outline
                                          : Icons.paid_outlined,
                                      size: 16,
                                      color: matched
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : Theme.of(context).colorScheme.error,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        matched
                                            ? 'All teams fully paid'
                                            : 'Remaining: ${MoneyCalculator.format(remaining)}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                              color: matched
                                                  ? Theme.of(
                                                      context,
                                                    ).colorScheme.primary
                                                  : Theme.of(
                                                      context,
                                                    ).colorScheme.error,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Paid: ${MoneyCalculator.format(total)} of ${MoneyCalculator.format(amount)}',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.captionMuted,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                  if (_scope == ExpenseScope.segment) ...[
                    const SizedBox(height: 8),
                    _SegmentPicker(
                      journey: journeyValue,
                      selectedId: _segmentId,
                      onChanged: (id) {
                        setState(() => _segmentId = id);
                        _applyScopeDefaults(
                          members: members,
                          journey: journeyValue,
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      'Advanced options',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    children: [
                      _CategoryField(
                        value: _category,
                        customController: _categoryController,
                        onChanged: (v) => setState(() => _category = v),
                      ),
                      const SizedBox(height: 8),
                      _DateField(
                        value: _spentAt,
                        onChanged: (v) => setState(() => _spentAt = v),
                      ),
                      const SizedBox(height: 8),
                      const SectionHeader('Other people who paid'),
                      for (var i = 0; i < _otherPayers.length; i++)
                        _OtherPayerRow(
                          memberId: _otherPayers[i].memberId,
                          controller: _otherPayers[i].controller,
                          members: members,
                          onRemove: () {
                            setState(() {
                              _otherPayers[i].controller.dispose();
                              _otherPayers.removeAt(i);
                            });
                          },
                          onMemberChanged: (id) {
                            setState(() => _otherPayers[i].memberId = id);
                          },
                          onAmountChanged: () => setState(() {}),
                        ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () {
                            final available = members
                                .where(
                                  (m) =>
                                      m.id != _payerMemberId &&
                                      !_otherPayers.any(
                                        (p) => p.memberId == m.id,
                                      ),
                                )
                                .toList();
                            if (available.isEmpty) return;
                            setState(
                              () => _otherPayers.add(
                                _OtherPayer(
                                  memberId: available.first.id,
                                  controller: TextEditingController(),
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add another payer'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _SplitPreview(
                    groupAmountMinor: _groupAmountMinor,
                    externalMinor: _externalMinor ?? 0,
                    amountMinor: _amountMinor,
                    primaryPayer: _scope == ExpenseScope.team
                        ? (_teamPaymentRows().any(
                                (row) => row.memberId == _payerMemberId,
                              )
                              ? _payerMemberId
                              : (_teamPaymentRows().isEmpty
                                    ? _payerMemberId
                                    : _teamPaymentRows().first.memberId))
                        : _payerMemberId,
                    otherPayers: [
                      // Team payment rows (non-primary team payers)
                      if (_scope == ExpenseScope.team)
                        for (final row in _teamPaymentRows())
                          if (row.memberId != _payerMemberId)
                            _PayerEntry(
                              memberId: row.memberId,
                              amountMinor: row.amountMinor,
                            ),
                      // Individual other payers (all scopes)
                      for (final p in _otherPayers)
                        if (p.controller.text.trim().isNotEmpty)
                          _PayerEntry(
                            memberId: p.memberId,
                            amountMinor:
                                MoneyCalculator.parseToMinorOrNull(
                                  p.controller.text,
                                ) ??
                                0,
                          ),
                    ],
                    participants: members
                        .where((m) => _participants.contains(m.id))
                        .toList(),
                    members: members,
                    scope: _scope,
                    customShares: _customShares,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Builder(
                    builder: (context) {
                      final readyToSave = _scope == ExpenseScope.team
                          ? (_teamPaymentRows().isNotEmpty ||
                                    _otherPayersTotal > 0) &&
                                _participants.isNotEmpty
                          : _payerMemberId != null && _participants.isNotEmpty;
                      return FilledButton.icon(
                        onPressed:
                            _saving || !readyToSave || !_customSharesValid
                            ? null
                            : () => _submit(members: members),
                        icon: _saving
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check),
                        label: Text(
                          widget.isEditing ? 'Save changes' : 'Save expense',
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CustomShareInputs extends StatefulWidget {
  const _CustomShareInputs({
    required this.participants,
    required this.customShares,
    required this.groupAmountMinor,
    required this.onChanged,
  });
  final List<Member> participants;
  final Map<int, int> customShares;
  final int? groupAmountMinor;
  final ValueChanged<Map<int, int>> onChanged;

  @override
  State<_CustomShareInputs> createState() => _CustomShareInputsState();
}

class _CustomShareInputsState extends State<_CustomShareInputs> {
  final Map<int, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    for (final m in widget.participants) {
      _controllers[m.id] = TextEditingController(
        text: MoneyCalculator.formatNoSymbol(widget.customShares[m.id] ?? 0),
      );
    }
  }

  @override
  void didUpdateWidget(covariant _CustomShareInputs oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reconcile controllers with the current participant list. Participants
    // toggled on after switching to Custom scope may not have a controller
    // yet (create one), and removals must be disposed so nothing leaks.
    final currentIds = widget.participants.map((m) => m.id).toSet();
    final stale = _controllers.keys
        .where((id) => !currentIds.contains(id))
        .toList();
    for (final id in stale) {
      _controllers.remove(id)?.dispose();
    }
    for (final m in widget.participants) {
      final controller = _controllers.putIfAbsent(
        m.id,
        () => TextEditingController(
          text: MoneyCalculator.formatNoSymbol(widget.customShares[m.id] ?? 0),
        ),
      );
      final newText = MoneyCalculator.formatNoSymbol(
        widget.customShares[m.id] ?? 0,
      );
      if (controller.text != newText) {
        controller.text = newText;
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Enter share for each participant',
          style: theme.textTheme.labelMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final m in widget.participants)
          Row(
            children: [
              MemberAvatar(m.name, radius: 12),
              const SizedBox(width: 8),
              Expanded(
                child: AppMoneyField(
                  controller: _controllers[m.id]!,
                  label: m.name,
                  hintText: '0',
                  constraint: AppMoneyConstraint.requiredPositive,
                  maxMinor:
                      (widget.groupAmountMinor != null &&
                          widget.groupAmountMinor! > 0)
                      ? widget.groupAmountMinor
                      : null,
                  maxStrict: false,
                  maxExceededMessage: 'Share exceeds total.',
                  onChanged: (_) {
                    final minor =
                        MoneyCalculator.parseToMinorOrNull(
                          _controllers[m.id]!.text,
                        ) ??
                        0;
                    widget.onChanged({...widget.customShares, m.id: minor});
                  },
                ),
              ),
            ],
          ),
        const SizedBox(height: AppSpacing.sm),
        Builder(
          builder: (context) {
            final total = widget.groupAmountMinor ?? 0;
            final allocated = widget.customShares.values.fold<int>(
              0,
              (s, v) => s + v,
            );
            final difference = total - allocated;
            final matched = difference == 0;
            return Column(
              children: [
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Total: ${MoneyCalculator.format(total)}',
                      style: theme.textTheme.bodyMuted,
                    ),
                    Text(
                      'Allocated: ${MoneyCalculator.format(allocated)}',
                      style: theme.textTheme.bodyMuted.copyWith(
                        color: matched
                            ? null
                            : Theme.of(context).colorScheme.error,
                        fontWeight: matched ? null : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                if (!matched && total > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 16,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            difference > 0
                                ? '${MoneyCalculator.format(difference)} remaining to allocate'
                                : '${MoneyCalculator.format(-difference)} over-allocated',
                            style: theme.textTheme.bodyMuted.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _PayerEntry {
  const _PayerEntry({required this.memberId, required this.amountMinor});
  final int memberId;
  final int amountMinor;
}

class _OtherPayerRow extends StatelessWidget {
  const _OtherPayerRow({
    required this.memberId,
    required this.controller,
    required this.members,
    required this.onRemove,
    required this.onMemberChanged,
    required this.onAmountChanged,
  });
  final int memberId;
  final TextEditingController controller;
  final List<Member> members;
  final VoidCallback onRemove;
  final ValueChanged<int> onMemberChanged;
  final VoidCallback onAmountChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: DropdownButtonFormField<int>(
            initialValue: members.any((m) => m.id == memberId)
                ? memberId
                : (members.isNotEmpty ? members.first.id : null),
            isDense: true,
            isExpanded: true,
            // Explicit colors so the selected payer and the floating label
            // stay clearly readable on every form surface (never white).
            style: TextStyle(
              overflow: TextOverflow.ellipsis,
              color: theme.colorScheme.onSurface,
            ),
            decoration: InputDecoration(
              labelText: 'Who paid',
              isDense: true,
              labelStyle: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            items: [
              for (final m in members)
                DropdownMenuItem(value: m.id, child: Text(m.name)),
            ],
            onChanged: (v) {
              if (v != null) onMemberChanged(v);
            },
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          flex: 4,
          child: AppMoneyField(
            controller: controller,
            label: 'Amount',
            hintText: 'e.g. 800',
            constraint: AppMoneyConstraint.requiredPositive,
            onChanged: (_) => onAmountChanged(),
          ),
        ),
        SizedBox(
          width: 36,
          child: IconButton(
            tooltip: 'Remove',
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 20),
            color: Theme.of(context).colorScheme.error,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }
}

class _TeamMultiPicker extends StatelessWidget {
  const _TeamMultiPicker({
    required this.teams,
    required this.selectedIds,
    required this.onToggle,
  });

  final List<Team> teams;
  final List<int> selectedIds;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    if (teams.isEmpty) {
      return Text(
        'Create a team on the Teams screen first.',
        style: Theme.of(context).textTheme.captionMuted,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Apply to teams', style: Theme.of(context).textTheme.sectionTitle),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final team in teams)
              FilterChip(
                label: Text(team.name),
                selected: selectedIds.contains(team.id),
                onSelected: (_) => onToggle(team.id),
              ),
          ],
        ),
      ],
    );
  }
}

class _TeamPayerRow extends StatelessWidget {
  const _TeamPayerRow({
    required this.team,
    required this.members,
    required this.payerId,
    required this.amountController,
    required this.onPayerChanged,
    required this.onAmountChanged,
  });

  final Team team;
  final List<Member> members;
  final int? payerId;
  final TextEditingController? amountController;
  final ValueChanged<int> onPayerChanged;
  final VoidCallback onAmountChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = members.any((m) => m.id == payerId) ? (payerId ?? 0) : 0;
    final paidAmount = amountController != null
        ? MoneyCalculator.parseToMinorOrNull(amountController!.text) ?? 0
        : 0;
    final payerName = payerId != null && payerId! > 0
        ? members.where((m) => m.id == payerId).map((m) => m.name).firstOrNull
        : null;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.groups_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    team.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (members.isEmpty)
                  Text('No members', style: theme.textTheme.captionMuted),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            DropdownButtonFormField<int>(
              initialValue: selected,
              isDense: true,
              isExpanded: true,
              // Explicit colors keep the "Who paid for this team" label and
              // its selected value readable on every surface (never white).
              style: TextStyle(color: theme.colorScheme.onSurface),
              decoration: InputDecoration(
                labelText: 'Who paid for this team',
                labelStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
              ),
              items: [
                const DropdownMenuItem<int>(
                  value: 0,
                  child: Text(
                    'No one — covered by another team',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                for (final m in members)
                  DropdownMenuItem(
                    value: m.id,
                    child: Text(m.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: members.isEmpty
                  ? null
                  : (v) {
                      if (v != null) onPayerChanged(v);
                    },
            ),
            if (payerId != null &&
                payerId! > 0 &&
                amountController != null &&
                members.any((m) => m.id == payerId)) ...[
              const SizedBox(height: AppSpacing.xs),
              AppMoneyField(
                controller: amountController!,
                label: 'Amount paid by this team',
                hintText: 'e.g. 2000',
                constraint: AppMoneyConstraint.requiredPositive,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                onChanged: (_) => onAmountChanged(),
              ),
              // Real-time payment status for this team
              if (paidAmount > 0 && payerName != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withAlpha(60),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.paid_outlined,
                        size: 14,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '$payerName paid ${MoneyCalculator.format(paidAmount)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _SegmentPicker extends StatelessWidget {
  const _SegmentPicker({
    required this.journey,
    required this.selectedId,
    required this.onChanged,
  });
  final JourneyView? journey;
  final int? selectedId;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final segments = journey?.segments ?? const <TravelSegment>[];
    if (segments.isEmpty) {
      return Text(
        'Create the journey on the Journey screen first.',
        style: Theme.of(context).textTheme.captionMuted,
      );
    }
    return DropdownButtonFormField<int>(
      initialValue: segments.any((s) => s.id == selectedId) ? selectedId : null,
      decoration: const InputDecoration(
        labelText: 'Travel segment',
        isDense: true,
      ),
      items: [
        for (final s in segments)
          DropdownMenuItem(
            value: s.id,
            child: Text(
              '${journey!.locationById(s.startLocationId)?.name ?? '?'} → ${journey!.locationById(s.endLocationId)?.name ?? '?'}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

class _ScopeOption extends StatelessWidget {
  const _ScopeOption({
    required this.scope,
    required this.label,
    required this.description,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final ExpenseScope scope;
  final String label;
  final String description;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected ? theme.colorScheme.primaryContainer.withAlpha(60) : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: selected ? theme.colorScheme.primary : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(description, style: theme.textTheme.captionMuted),
                  ],
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_circle,
                  size: 20,
                  color: theme.colorScheme.primary,
                )
              else
                Icon(
                  Icons.radio_button_unchecked,
                  size: 20,
                  color: theme.colorScheme.outline,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SplitPreview extends StatelessWidget {
  const _SplitPreview({
    required this.groupAmountMinor,
    required this.externalMinor,
    required this.amountMinor,
    required this.primaryPayer,
    required this.otherPayers,
    required this.participants,
    required this.members,
    required this.scope,
    required this.customShares,
  });
  final int? groupAmountMinor;
  final int externalMinor;
  final int? amountMinor;
  final int? primaryPayer;
  final List<_PayerEntry> otherPayers;
  final List<Member> participants;
  final List<Member> members;
  final ExpenseScope scope;
  final Map<int, int> customShares;

  /// Build a map of memberId → total amount paid from primary + other payers.
  Map<int, int> _buildPaidMap() {
    final paid = <int, int>{};
    final primaryAmount = groupAmountMinor ?? 0;
    if (primaryPayer != null && primaryAmount > 0) {
      // Primary payer covers the group amount minus what other payers cover.
      final othersTotal = otherPayers.fold<int>(
        0,
        (sum, p) => sum + p.amountMinor,
      );
      final primaryPaid = primaryAmount - othersTotal;
      if (primaryPaid > 0) {
        paid[primaryPayer!] = primaryPaid;
      }
    }
    for (final p in otherPayers) {
      paid[p.memberId] = (paid[p.memberId] ?? 0) + p.amountMinor;
    }
    return paid;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groupAmount = groupAmountMinor;
    if (groupAmount == null || groupAmount <= 0 || participants.isEmpty) {
      return const SizedBox.shrink();
    }
    final paidMap = _buildPaidMap();
    final totalPaid = paidMap.values.fold<int>(0, (sum, v) => sum + v);
    final totalAmount = amountMinor ?? (groupAmount + externalMinor);
    final isFullyPaid = totalPaid >= totalAmount;
    final remaining = totalAmount - totalPaid;
    final shares = scope == ExpenseScope.custom
        ? <MemberShare>[]
        : const EqualExpenseSplitter().split(
            totalMinor: groupAmount,
            memberIds: [for (final m in participants) m.id],
          );
    final splitTotal = shares.fold<int>(0, (sum, s) => sum + s.amountMinor);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Split preview', style: theme.textTheme.sectionTitle),
            const SizedBox(height: AppSpacing.sm),
            // Payment status banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: isFullyPaid
                    ? theme.colorScheme.primaryContainer.withAlpha(80)
                    : totalPaid > 0
                    ? theme.colorScheme.tertiaryContainer.withAlpha(80)
                    : theme.colorScheme.surfaceContainerHighest.withAlpha(120),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    isFullyPaid
                        ? Icons.check_circle_outline
                        : totalPaid > 0
                        ? Icons.paid_outlined
                        : Icons.pending_outlined,
                    size: 16,
                    color: isFullyPaid
                        ? theme.colorScheme.primary
                        : totalPaid > 0
                        ? theme.colorScheme.tertiary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isFullyPaid
                          ? 'Fully paid'
                          : totalPaid > 0
                          ? 'Paid ${MoneyCalculator.format(totalPaid)} of ${MoneyCalculator.format(totalAmount)} · Remaining ${MoneyCalculator.format(remaining)}'
                          : 'No payments recorded yet',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isFullyPaid
                            ? theme.colorScheme.primary
                            : totalPaid > 0
                            ? theme.colorScheme.tertiary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (scope == ExpenseScope.custom) ...[
              for (final m in participants)
                _SplitMemberRow(
                  name: m.name,
                  shareMinor: customShares[m.id] ?? 0,
                  paidMinor: paidMap[m.id] ?? 0,
                ),
              const Divider(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text('Total', style: theme.textTheme.bodyMuted),
                  ),
                  MoneyText(groupAmount, style: theme.textTheme.statValue),
                ],
              ),
            ] else ...[
              for (var i = 0; i < shares.length; i++)
                _SplitMemberRow(
                  name: participants[i].name,
                  shareMinor: shares[i].amountMinor,
                  paidMinor: paidMap[participants[i].id] ?? 0,
                ),
              const Divider(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Total (split)',
                      style: theme.textTheme.bodyMuted,
                    ),
                  ),
                  MoneyText(splitTotal),
                ],
              ),
              if (externalMinor > 0) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'External (not shared)',
                        style: theme.textTheme.bodyMuted,
                      ),
                    ),
                    MoneyText(externalMinor),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Paid by the payer',
                        style: theme.textTheme.bodyMuted,
                      ),
                    ),
                    MoneyText(
                      groupAmount + externalMinor,
                      style: theme.textTheme.statValue,
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// A single row in the split preview showing name, share, paid, and net.
class _SplitMemberRow extends StatelessWidget {
  const _SplitMemberRow({
    required this.name,
    required this.shareMinor,
    required this.paidMinor,
  });

  final String name;
  final int shareMinor;
  final int paidMinor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final net = paidMinor - shareMinor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          MemberAvatar(name, radius: 12),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: theme.textTheme.bodyMedium),
                if (paidMinor > 0)
                  Text(
                    'Paid ${MoneyCalculator.format(paidMinor)}',
                    style: theme.textTheme.captionMuted,
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              MoneyText(shareMinor),
              if (paidMinor > 0)
                Text(
                  net >= 0
                      ? '+${MoneyCalculator.format(net)}'
                      : '-${MoneyCalculator.format(-net)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: net > 0
                        ? theme.colorScheme.primary
                        : net < 0
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategoryField extends StatelessWidget {
  const _CategoryField({
    required this.value,
    required this.customController,
    required this.onChanged,
  });
  static const _categories = [
    'Transport',
    'Food',
    'Accommodation',
    'Activities',
    'Shopping',
    'Misc',
  ];
  static const _icons = {
    'Transport': Icons.train_outlined,
    'Food': Icons.restaurant_outlined,
    'Accommodation': Icons.hotel_outlined,
    'Activities': Icons.hiking_outlined,
    'Shopping': Icons.shopping_bag_outlined,
    'Misc': Icons.more_horiz,
  };
  final String? value;
  final TextEditingController customController;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      for (final cat in _categories)
        FilterChip(
          label: Text(cat),
          avatar: Icon(_icons[cat], size: 16),
          selected: value == cat,
          onSelected: (sel) => onChanged(sel ? cat : null),
          visualDensity: VisualDensity.compact,
        ),
      ActionChip(
        label: const Text('Custom…'),
        avatar: const Icon(Icons.edit_outlined, size: 16),
        onPressed: () => _showCustomDialog(context),
        visualDensity: VisualDensity.compact,
      ),
    ],
  );

  void _showCustomDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custom category'),
        content: TextField(
          controller: customController,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Category name'),
          maxLength: 50,
          onSubmitted: (_) {
            Navigator.pop(ctx);
            onChanged(
              customController.text.trim().isEmpty
                  ? null
                  : customController.text.trim(),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              onChanged(
                customController.text.trim().isEmpty
                    ? null
                    : customController.text.trim(),
              );
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.value, required this.onChanged});
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = value != null ? DateFormats.date(value!) : 'Today';
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          firstDate: DateTime(2020),
          lastDate: DateTime(now.year + 1),
        );
        onChanged(picked);
      },
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Date',
          suffixIcon: const Icon(Icons.calendar_today, size: 20),
          suffixIconColor: theme.colorScheme.onSurfaceVariant,
        ),
        child: Text(text, style: theme.textTheme.bodyLarge),
      ),
    );
  }
}
