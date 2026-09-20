# TripSplit

**Split trip expenses. Fairly. Offline-first.**

TripSplit is a mobile application for tracking and settling shared expenses during group trips. Built with Flutter (Android), it uses a local SQLite database as the sole source of truth, so the core experience works entirely without a network connection.

---

## Problems Solved

### 1. Settling debts after a trip

When friends travel together, someone always pays for trains, hotels, or meals on behalf of others. By trip's end, nobody remembers who is out how much. TripSplit tracks every expense, every payment, and every contribution, then computes exact net positions for each member so the group can settle up fairly.

### 2. Fair and precise splitting with zero rounding error

All monetary values are stored as integer minor units (paise for INR). The equal-split strategy uses a largest-remainder distribution algorithm: everyone receives the floor division first, then leftover paise are distributed one at a time. This guarantees that splits always sum exactly to the original amount. For example, ₹733.60 split four ways yields ₹183.40 per head with no residual. ₹10.00 split three ways yields ₹3.34 + ₹3.33 + ₹3.33 = ₹10.00 exactly.

### 3. Complex real-world payment scenarios

- **Multiple payers per expense** — A single expense can have several people contributing different amounts (e.g., two people splitting a hotel bill). Each payer's out-of-pocket is tracked independently via `ExpensePayment` rows.
- **External (non-group) payments** — A portion of an expense can be paid to people or items outside the group. This external amount is excluded from splitting and from debt calculations, so only the group-shareable portion creates obligations.
- **Selected participants** — Not everyone in the trip needs to be included in every expense. Participants are chosen explicitly per expense.
- **Single-payer expenses** — The common case where one person pays the full amount for a subset of members.

### 4. Minimizing the number of settlements

A team-aware obligation-graph algorithm computes a compact set of transfers. Members are grouped into teams via real team membership (the `team_members` rows, not expense shares). Each member's obligations are counted against the corresponding payer directly, opposing obligations between the same pair are netted, and multi-payer team expenses keep non-payer members inside their own team — every non-payer participant's share is covered by the payers who funded their teams (split proportionally to how much each fronted, plus any generic payers), and only payers balance the residual differences between teams. When no team context exists, a greedy largest-debt-first match produces the fewest possible transfers (debtors by largest debt, creditors by largest credit, matched until all nets are zero).

### 5. Partial payment tracking

Real-world repayments happen in installments. TripSplit tracks how much of each planned transfer has actually been paid (`amountPaidMinor` on `Settlement`). Partial payments decay the remaining nets, and the settlement status is derived as outstanding / partial / paid. Recording a payment recalculates all remaining obligations accordingly.

### 6. Journey-aware expense attribution

Members can join or leave a trip at different points along a route. The journey model defines ordered locations (e.g., Erode → Salem → Bengaluru) and travel segments between them. Each member has optional `joinLocationId` and `leaveLocationId` fields. When a segment-based expense is created, the `ParticipationCalculator` determines which members were actually present during that leg, and those members become the default participants. Users can always override the defaults.

### 7. Offline reliability

All data lives on-device in SQLite (via Drift). No backend, no internet dependency. The app has been verified to complete its full flow with networking forcibly disabled (`HttpOverrides` that throw on any socket creation).

---

## Implemented Features

### Trip Management

- **Create a trip** with name, description, currency (defaults to INR), planned budget, start location, and date range.
- **Trip dashboard** showing trip identity, budget/remaining tokens, and navigation cards to all sub-sections.
- **Home screen** listing all trips with summary cards (member count, expense count, budget progress).
- **Atomic trip creation** — a trip, its members, and their contributions are inserted in a single database transaction with full rollback on failure.

### Member Management

- **Add members** to a trip with a name.
- **Rename members** with duplicate-name detection (catches the case where renaming onto an existing member's name).
- **Remove members** from a trip.
- **Member detail screen** showing per-member financial breakdown.
- **Join/leave location tracking** — each member can have a join and leave location along the journey route, driving segment participation defaults.

### Contributions

- **Record cash contributions** each member puts into the trip pool (strictly positive amounts only).
- **Add contributions** via a dedicated screen with guarded money input.
- Contributions are used to calculate each member's `cashRemaining` — the money they still have available from the pool.

### Expense Management

- **Record expenses** with amount, description (max 200 characters), payer, participants, and split strategy.
- **Five expense scopes:**
  - `individual` — one person's own purchase; participants default to the payer alone.
  - `shared` — a plain split between explicitly selected participants.
  - `team` — scoped to a team's members as default participants.
  - `segment` — scoped to members who travelled a specific travel segment.
  - `custom` — explicitly chosen participants, no automatic defaults.
- **External (non-group) amount** — a portion of the expense paid to non-group people/items, excluded from splitting and debt calculations.
- **Live split preview** on the expense form showing Total (split) / External / Paid by the payer, with per-share amounts in real time.
- **Edit expenses** with full share rewriting and correct prefill (uses `MoneyCalculator.formatNoSymbol` instead of float division).
- **Delete expenses** with automatic share cascade.
- **Expense categories** via an optional `category` field.
- **Expense details screen** showing External (not shared) / Group share breakdown rows.

### Balance Calculation

Five distinct per-member financial figures, always computed at read time (never stored):

1. **Contribution** — cash brought into the trip pool.
2. **Actual paid** — total expense money the member actually laid out of pocket (including any external, non-group portion).
3. **Expense share** — total expense responsibility assigned to the member.
4. **Net position** — group outlay (amount paid minus the external portion) minus expense share. Positive = owed money, negative = owes money, zero = balanced.
5. **Cash remaining** — contributions plus settlements received minus actual payments minus settlements paid out.

Aggregate figures: total contributions, total group expenses, remaining budget, total outstanding debt, total cash remaining across all members.

### Settlement Engine

- **Team-aware settlement planning** — non-payer members are mapped to the payers who funded their own team (real `team_members` membership), payer imbalances between teams are balanced as payer-only edges, and obligations are netted per pair into deterministic `SettlementSuggestion` objects (from → to → amount). Payer-balance edges between teams are surfaced on the team settlement screen. Without team context a greedy largest-debt-first match minimizes transfer count.
- **Record settlements** (transfers between members) with obligation amount and paid amount.
- **Partial settlement support** — multiple payments accumulate until the transfer is fully paid.
- **Settlement status** derived as outstanding / partial / paid.
- **Team-scoped settlements** — view settlements scoped to a specific team.
- **Settlements never modify spending or budget** — they are transfers, not expenses.

### Journey System

- **Trip locations** — named places on the trip route (e.g., "Erode", "Salem", "Bengaluru").
- **Travel segments** — ordered legs between locations with optional start/end times and a sequence number.
- **Member segment participations** — explicit per-member, per-segment participation records that override the derived defaults.
- **Participation calculator** — derives who participated in each segment from join/leave locations when no explicit participation record exists.
- **Journey screen** for managing locations, segments, and per-member participation.

### Team System

- **Create teams** to organize trip members into sub-groups.
- **Rename and delete teams** — deletion fails while expenses reference the team, requiring reassignment first.
- **Add/remove team members** — team membership drives default participants for team-scoped expenses and keeps settlement obligations inside each team.
- **Team settlement screen** — view settlements scoped to a specific team.

### Input Validation (Multi-Layer)

- **UI validators** — form fields validate inline (negative amounts, empty names, malformed input, max description length).
- **Repository validation** — catches duplicate trip names, duplicate member names (on add and rename), zero contributions, negative budgets, empty descriptions, over-long descriptions, external amount >= expense amount.
- **Calculator invariants** — balance and settlement calculators reject negative shares, negative expenses, and invalid external amounts.
- **SQLite constraints** — foreign keys enforced, `CHECK`-style constraints via repo, unique constraints via `SqliteException` error code 2067 handling.
- **Negative money rejected** — inputs containing `-` are caught at parse time with a clear "cannot be negative" message, not silently converted.
- **Empty/whitespace/malformed input** rejected with specific error messages.

### Currency & Formatting

- **Integer minor units** — all monetary values stored as integers (paise), never floating-point.
- **Indian number grouping** — amounts formatted as ₹12,34,567 (rightmost group of three, then groups of two).
- **Currency symbol** — ₹ prefix on formatted amounts.
- **`formatNoSymbol`** — used for edit prefill to avoid double-symbol issues.
- **Negative amount display** — renders as `-₹198.80`.

### First-Run Experience

- **Splash screen** — holds for ≥650ms, then routes to Home (returning user) or Welcome (first run).
- **Welcome screen** — brand lockup (luggage icon mark + wordmark), value proposition bullets, "Get started" and "Skip tour" actions.
- **Onboarding tour** — 3-step PageView ("Plan the budget", "Split expenses fairly", "Settle up, offline") with progress bar, Back/Next/Skip, and completion persistence via `shared_preferences` so the tour never replays.

### Design System & UI

- **Material 3 theme** with token-first design: `AppColors`, `AppSpacing`, `AppRadius`, `AppElevation`, `AppIconSizes`, `AppTextStyles`.
- **Financial colors** — `AppFinancialColors` ThemeExtension with receives/owes/info palettes, accessed via `context.financial`. Money never uses color as the only signal.
- **Reusable component library:**
  - `StatusChip` + `StatusTone` — success/warning/info/neutral/danger pills, always label-carrying, exposed to screen readers via `Semantics`.
  - `MemberAvatar` — initials-based avatar.
  - `AppMoneyField` + `AppMoneyConstraint` — standardized money input with number keyboard, label/hint/helper, and validation for negative/positive/max-minor.
  - `AppConfirmationDialog` — destructive vs. primary tinting, explicit cancel.
  - `SectionHeader` — grouped section titles with optional trailing action.
  - `LoadingState`, `EmptyState`, `AsyncValueView` — standard async/empty/loading primitives.
  - `MoneyText` — formatted money display widget.
- **SafeArea** applied bottom on every screen.
- **Keyboard dismissal** — `ScrollViewKeyboardDismissBehavior.onDrag` on every scrollable screen.
- **Responsive** — tested at 360×640, 390×844, 430×932 breakpoints plus 1.3× text scale with zero overflow exceptions.
- **Native launch polish** — Android `windowBackground` set to brand green for seamless cold start.

### Screens (16 total)

1. Splash
2. Welcome
3. Onboarding (3-step tour)
4. Home (trip list)
5. Create Trip
6. Trip Dashboard
7. People / Members
8. Add Member
9. Add Contribution
10. Member Detail
11. Expense List
12. Expense Details
13. Expense Form (create + edit)
14. Balances
15. Settlements
16. Record Settlement

Plus: Journey, Teams, Team Settlement.

### Error Handling

Sealed `AppException` hierarchy:
- `DatabaseException` — wraps `SqliteException` with optional native error code.
- `ValidationException` — user input or domain invariant failures.
- `RepositoryException` — repository-level operation failures.

### Architecture & Infrastructure

- **Feature-first Clean Architecture:** Presentation → Domain → Data.
- **Riverpod** dependency injection.
- **GoRouter** navigation with named routes and route constants.
- **Drift (SQLite)** with migration strategy (schema version 4), foreign keys enforced, WAL mode.
- **Freezed + json_serializable** for immutable domain models.
- **13 database tables:** Trips, Members, Locations, TravelSegments, MemberSegmentParticipations, Teams, TeamMembers, Contributions, Expenses, ExpenseShares, ExpensePayments, Settlements, Notes.
- **6 DAOs:** TripDao, MemberDao, ContributionDao, ExpenseDao, SettlementDao, JourneyDao.
- **Schema migrations:** v1→v2 (budget, timestamps, partial settlements), v2→v3 (external amount), v3→v4 (journey model, teams, expense scopes, multi-payer).
- **In-memory database** for tests (`NativeDatabase.memory()`), file-backed on device.
- **Docker development environment** with Makefile.
- **GitHub Actions CI** (format, analyze, test, build).

### Testing

- **1,045+ unit/widget tests** including 900 randomized property-based assertions over 300 fictional trips verifying financial invariants at scale.
- **3 on-device integration tests** including offline proof with network blocking.
- **Responsive smoke tests** at 3 breakpoints + large text scale.
- **Input validation matrix** covering empty, malformed, negative, over-precise, and duplicate inputs at UI, repository, and calculator layers.
- **Schema migration tests** verifying upgrade paths (1→3, 2→3, 3→4).
- **Persistence tests** verifying data survives database reopen.
