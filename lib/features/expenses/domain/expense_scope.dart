/// What an expense applies to.
///
/// The scope drives how participants are DEFAULTED in the UI and how the
/// expense is described. The authoritative participant list always remains the
/// explicit per-expense shares; scopes never force participation.
enum ExpenseScope {
  /// One person's own purchase; participants default to the payer alone.
  individual,

  /// A plain split between explicitly selected participants.
  shared,

  /// Applies to a team; participants default to the team's members.
  team,

  /// Applies to a travel segment; participants default to the members who
  /// actually travelled that segment.
  segment,

  /// Explicitly chosen participants, no automatic defaults.
  custom,
}

extension ExpenseScopeName on ExpenseScope {
  String get apiValue => switch (this) {
    ExpenseScope.individual => 'individual',
    ExpenseScope.shared => 'shared',
    ExpenseScope.team => 'team',
    ExpenseScope.segment => 'segment',
    ExpenseScope.custom => 'custom',
  };

  static ExpenseScope fromApiValue(String value) => switch (value) {
    'individual' => ExpenseScope.individual,
    'team' => ExpenseScope.team,
    'segment' => ExpenseScope.segment,
    'custom' => ExpenseScope.custom,
    _ => ExpenseScope.shared,
  };

  String get label => switch (this) {
    ExpenseScope.individual => 'Individual',
    ExpenseScope.shared => 'Shared',
    ExpenseScope.team => 'Team',
    ExpenseScope.segment => 'Segment',
    ExpenseScope.custom => 'Custom',
  };
}
