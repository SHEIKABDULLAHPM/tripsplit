# TripSplit Production UI/UX Report

## 58.12 Purpose

This report documents the production-grade UI/UX overhaul of the TripSplit app:
the design system and Material 3 theme, the Splash/Welcome/Onboarding first-run
experience, the full redesign of every screen, reusable component library,
responsive/safe-area/keyboard/accessibility polish, and the automated UI test
coverage proving the UI ships clean. It also confirms **functional regression**
— every financial behavior preserved by the redesign is still verified by the
existing engine tests — and a device/test matrix for responsiveness.

## 58.13 Date & Snapshot

- 2026-09-14.
- Flutter 3.44.9 (host) / 3.44.0 (`trip_split_dev` Docker image), Dart 3.12,
  Riverpod 3, Drift 2.35, `AppConstants.databaseSchemaVersion == 3`.
- Repository has no commits yet (branch `main`, working tree untracked);
  snapshot identity is the working tree as of 2026-09-14.

## 58.14 UI Quality

### Design system

A token-first design system now lives under `lib/app/theme/`:
`app_colors.dart` (Material-palette colors + financial colors), `app_spacing.dart`,
`app_radius.dart` (xs4/sm8/md12/lg16/xl24), `app_elevation.dart` (0/1/2/4/8),
`app_icon_sizes.dart` (16/20/24/32/48/64), `app_text_styles.dart`
(display/headline/title/body/label/caption tiers incl. `captionMuted`), and
`app_financial_colors.dart` — a `ThemeExtension` surfaced as `context.financial`
with `receives`/`owes`/`info` palettes so money never uses a color as the only
signal. `app_theme.dart` centralizes one `ThemeData` (`AppTheme.light`) with a
complete Material 3 into: card, dialog, bottom-sheet, list-tile, snackbar,
filled/outlined/text button, FAB, progress indicator, text selection, navigation
bar, divider, and tooltip themes.

### Shared components

`lib/core/widgets/` provides the reusable primitives the redesign is built on:
`SectionHeader` (grouped section titles with optional trailing action),
`StatusChip` + `StatusTone` (success/warning/info/neutral/danger pills, always
label-carrying so color is never the only signal), `AppConfirmationDialog` +
`showAppConfirmation` (destructive vs. primary tinting, explicit cancel),
`MemberAvatar` (initials avatar), `AppMoneyField` + `AppMoneyConstraint`
(single shared money input: number keyboard, label/hint/helper, negative /
positive / max-minor validation), `LoadingState`, `EmptyState`, `AsyncValueView`
(single-builder async view), and `DateFormats`. `AppMoneyField` renders exactly
one `TextFormField`, preserving existing structural test finders.

### First-run experience

A Splash → Welcome → Onboarding flow was added with no new dependencies
(Reed `shared_preferences`, already in the manifest, via `OnboardingPrefs`).
- `SplashScreen` holds for ≥ 650 ms, then routes to Home (returning user) or
  Welcome (first run) using `go_router` (`AppRouter` initial route `/splash`).
- `WelcomeScreen` — brand lockup (`BrandLockup`: luggage icon mark + wordmark),
  value bullets, "Get started" and "Skip tour".
- `OnboardingScreen` — 3-step `PageView` ("Plan the budget", "Split expenses
  fairly", "Settle up, offline") with progress bar, Back/Next + Skip, and a
  single "Get started" completing step; completion persists
  `onboarding_completed=true` so the tour never replays.
- Native polish: Android launch `windowBackground` set to the brand green
  (`#FF2E7D57`) in `values/styles.xml` and `values-night/styles.xml`, so the
  transition from cold start is seamless.

### Every screen redesigned

All 13 screens were rebuilt on the design system:
- Home (`HomeScreen`) — hero empty state, trip cards (name, member count,
  budget tokens, remaining labels), "Create trip".
- `CreateTripScreen` — grouped fields with validation, member builder rows.
- `TripDashboardScreen` — header with trip identity, budget/remaining tokens,
  navigation action cards (People, Expenses, Balances, Settlements).
- `PeopleScreen`, `AddMemberScreen`, `AddContributionScreen` — avatar rows,
  per-member cash/contribution columns, guarded money fields.
- `ExpenseListScreen`, `ExpenseDetailsScreen`, `ExpenseFormScreen` —
  grouped expense list, details with External (not shared) / Group share rows
  and the live split-preview (Total (split) / External / Paid by the payer,
  per-share amounts), description/amount/payer/participants form with
  `maxLength: 200`.
- `BalancesScreen` — "Group summary" (5 distinct figures) + "Per member"
  section with net-position labels and `StatusChip` per member.
- `SettlementsScreen` — suggested-transfer list + recorded-payment history.
- `RecordSettlementScreen` — transfer/payment sections.

A global polish pass applied `SafeArea(bottom: true)` and
`ScrollViewKeyboardDismissBehavior.onDrag` to every screen, plus a consistent
`Formatting` baseline: `₹` Indian grouping, `formatNoSymbol` for edit prefill,
semantics labels on all status pills, date formatting via `DateFormats`.

## 58.15 Functional Regression

The hard constraint was honored: no business behavior changed. The financial
engine, schema (v3), offline-first storage, and validation chains were
untouched; only presentation layer changed. The redesign is verified by the
existing suite plus new UI tests.

### Gates (all green at report time)

| Gate | Command | Result |
|---|---|---|
| Format | `dart format .` | clean (116 files) |
| Analyzer (host) | `flutter analyze` | 0 errors / 0 warnings / 0 infos |
| Analyzer (Docker) | `flutter analyze` in `trip_split_dev` | 0 issues |
| Unit + widget | `flutter test` | **1045/1045 pass** |
| Integration | `flutter test integration_test/... (emulator-5554)` | **3/3 pass** |
| Debug APK | `flutter build apk --debug` (Docker) | built, 170 MB |
| Release APK | `flutter build apk --release` (Docker) | built, 59.5 MB |
| Release launch | install + launch on emulator-5554 | MainActivity focused, no logcat errors |

### Unit + widget breakdown (1045)

| Suite (new this iteration) | Tests | What it proves |
|---|---|---|
| `test/app/onboarding_flow_test.dart` | 4 | Splash → Welcome → all 3 tour pages → Home; welcome "Skip tour"; onboarding "Skip"; returning user skips tour & prefs flag persisted |
| `test/core/widgets/core_widgets_test.dart` | 6 | `StatusChip` uppercase label + semantics, `SectionHeader` title + trailing action, `AppConfirmationDialog` confirm→true / cancel→false |
| `test/core/widgets/app_money_field_test.dart` | 6 | Shared validator: required-empty, zero rejection, tailored negative message, standard fallback, malformed → 'Enter a valid amount.', max-minor strict guard |
| `test/ui/responsive_smoke_test.dart` | 24 | The 6 core screens at 360×640 / 390×844 / 430×932 + all 6 at 1.3× text scale — zero overflow exceptions via `tester.takeException()` |

Plus pre-existing suites: 900 randomized oracle/property assertions (balances,
settlements, budgets, cash) over 300 fictional trips, money parsing, expense
split rounding, tech-horizon scenarios, repository/DAO/persistence/migration
tests, and the updated `app_start_test.dart` / `router_test.dart` which
now cover the splash route with mock prefs.

### Integration (on-device, `mindease_android` emulator)

- `app_test.dart` (2 tests): app launches Home and renders 'Trips' /
  'No trips yet', and creates a real empty local SQLite DB + navigates to the
  new-trip form.
- `offline_test.dart`: all core flow with `HttpOverrides` that throw on any
  socket creation — proving zero network dependence end-to-end.
- Both now set `onboarding_completed` via the real plugin before pumping so
  they deterministically exercise the returning-user path.

## 58.16 Responsive & Accessibility Test Matrix

Responsive smoke tests pump the rebuilt screens at three breakpoints plus a
large-text run; `tester.takeException()` catches RenderFlex overflows as
failures. No overflows were found.

| Screen | 360×640 | 390×844 | 430×932 | 390×844 @ 1.3× scale |
|---|---|---|---|---|
| Home | PASS | PASS | PASS | PASS |
| Trip Dashboard | PASS | PASS | PASS | PASS |
| People | PASS | PASS | PASS | PASS |
| Balances | PASS | PASS | PASS | PASS |
| Settlements | PASS | PASS | PASS | PASS |
| Expense List | PASS | PASS | PASS | PASS |

Accessibility conventions applied app-wide and guarded by tests: `StatusChip`
exposes its label via `Semantics`; `AppMoneyField` keeps Flutter's default
field semantics; confirmation dialogs expose title + message; text is never
color-only. Large text scale (1.3×) introduces no overflow on any covered
screen.

## 58.17 Audit / Fix Classification During Rewrite

| # | Severity | Finding | Fix |
|---|----------|---------|-----|
| 1 | HIGH | `BrandLockup` typed `switch` results as `double` on `int` literals | Removed the type witnesses (literals made `double`) |
| 2 | HIGH | People screen referenced `theme` before declaration inside `build` | Added `final theme = Theme.of(context);` at top of `build` |
| 3 | MEDIUM | Local `MemberBalanceRow` shadowed the domain `MemberBalance` model on the Balances screen | Removed local class; imported `core/calculations/balances.dart` |
| 4 | MEDIUM | Dead `StatusToneBuilders.forNetLabel` extension (namespace-anchored static, unused) | Removed |
| 5 | MEDIUM | `InputDecoration` `inputShape` leftover in theme | Removed unused variable |
| 6 | LOW | Duplicate `_NavActionCard` declaration on trip dashboard | Removed duplicate class |
| 7 | LOW | Unused imports across screens / dup: `money.dart` twice in `people_screen` | Pruned all |
| 8 | LOW | `const` on runtime-context icon color — const expression error / non-const constructor use | Dropped const where runtime value required |
| 9 | LOW | `_SplitPreview` header + row double-rendered `₹365.40`, breaking amount-finder contract | Header shows caption only; single row total |
| 10 | LOW | Integration tests asserted old layout and would land on Welcome on real prefs | Updated assertions + seeded `onboarding_completed` |
| 11 | INFO | 24 analyzer lints (const constructors, omit types, expression bodies, unnecessary lambdas, directives ordering, null-aware elements) | All resolved; analyzer at 0 issues |
| 12 | INFO | Formatting drift | `dart format` clean across lib + test |

No CRITICAL/HIGH remains. All findings above are presentation-layer only and
none altered business behavior.

## 58.18 Open / Deferred Items

1. Dark mode: `AppTheme.light` is the single theme. A dark theme was not added
   in this iteration (kept scope tight). Severity: LOW.
2. `BrandLockup` uses the `Icons.luggage` icon mark because `assets/` is empty;
   a bitmap/font logo can be dropped in behind the same lockup. Severity: LOW.
3. Member-group paste / bulk-import and trip delete UI remain deferred from the
   QA audit (feature gaps, not defects).

## 58.19 Final Verdict

**YES** — TripSplit ships with a coherent Material 3 design system, a polished
first-run onboarding flow, a completely redesigned screen set, shared
componentry, and responsive/accessibility hardening. Functional regression is
fully guarded: **1045/1045** unit+widget tests, **3/3** on-device integration
tests (incl. hard offline), analyzers clean on host and in Docker,
debug + release APKs build in the `trip_split_dev` container, and the release
APK installs and launches on the emulator with a clean logcat. No functional
defect was introduced; no CRITICAL/HIGH UI defect remains.