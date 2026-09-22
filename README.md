# TripSplit

**Split trip expenses. Fairly. Offline-first.**

TripSplit is a mobile application for tracking shared trip expenses. It is built
with Flutter and uses a local SQLite database as the source of truth, so the
core experience works entirely without a network connection.

> **Current phase:** project foundation. The complete expense-sharing,
> balance-calculation, and settlement engine (members, contributions, expenses,
> splitting, balances, and payback) is implemented in the next phase. This
> repository currently provides the professional architecture, database,
> tooling, and Docker environment those features will build on.

---

## Overview

- **Offline-first:** no backend is required to use the app. All data lives in a
  local SQLite database (managed with Drift).
- **Clean Architecture:** feature-first layout with strict dependency direction:
  Presentation → Domain → Data.
- **Reproducible development:** the entire Flutter toolchain runs inside a
  Docker container driven through `make`.
- **Testable:** Riverpod dependency injection, repository interfaces, and an
  in-memory database mode make every layer testable.

## Architecture

The codebase follows a feature-first Clean Architecture:

```
Presentation  →  Domain  →  Data
```

- **Presentation** layer is Flutter widgets and Riverpod state. It depends only
  on domain abstractions.
- **Domain** layer contains entities and repository interfaces. It is pure Dart
  and has no Flutter or database dependencies.
- **Data** layer persists domain entities. It is implemented with Drift DAOs
  backed by SQLite.

Dependency rules:

- Presentation must **not** access Drift tables directly.
- Domain must **not** depend on Flutter UI.
- Business logic must **not** live inside widgets.
- Database implementation stays inside the data/infrastructure layer.

## Technology Stack

| Concern            | Choice                                   |
| ------------------ | ---------------------------------------- |
| Framework          | Flutter (Material 3)                     |
| Language           | Dart                                     |
| State management   | Riverpod (`flutter_riverpod`)            |
| Navigation         | GoRouter                                 |
| Local database     | Drift + SQLite (`sqlite3_flutter_libs`)  |
| JSON / models      | `freezed` + `json_serializable`          |
| Linting            | `flutter_lints`                          |
| Code generation    | `build_runner`                           |
| Development env    | Docker + Docker Compose + `make`         |
| CI                 | GitHub Actions                           |

## Project Structure

```
lib/
├── app/                 # App shell: root widget, router, theme
│   ├── app.dart
│   ├── router.dart
│   ├── widgets/
│   └── theme/
├── core/                # Framework-level building blocks
│   ├── constants/
│   ├── errors/
│   ├── extensions/
│   ├── utils/
│   └── widgets/
├── database/            # Drift schema, DAOs, migrations (data layer)
│   ├── app_database.dart
│   ├── tables/
│   └── daos/
├── features/            # Feature-first modules
│   ├── trips/
│   ├── members/
│   ├── contributions/
│   ├── expenses/
│   ├── balances/
│   └── settlements/
│       ├── data/        # repository implementations
│       ├── domain/      # entities + repository interfaces
│       └── presentation/ # screens + state
├── injection/           # Riverpod provider wiring
└── main.dart

test/                    # Unit & widget tests
integration_test/        # On-device integration tests
docker/                  # Dockerfile, entrypoint, doctor scripts
.github/workflows/       # CI
```

## Offline-First Strategy

- The **local SQLite database is the source of truth** for the MVP.
- All reads and writes go through the local Drift database; the app never
  requires a network call to function.
- Derived values such as balances are **computed, never stored**, so there is a
  single source of truth for every financial figure.
- A runtime Dart test (`HttpOverrides`) proves the app flow makes no network
  requests (`integration_test/offline_test.dart`).

## Local Database

The Drift database (`lib/database/app_database.dart`) defines the schema for
future entities:

- `trips`
- `members`
- `contributions`
- `expenses` (with `expense_shares`)
- `settlements`

Monetary values are stored as integer **minor units** (e.g. cents) for the
trip currency declared on the trip. Foreign keys are enforced (`PRAGMA
foreign_keys = ON`) and deletes are configured with cascade/restrict actions.
Schema changes are handled via the Drift `MigrationStrategy`; bump
`AppConstants.databaseSchemaVersion` together with new migration steps.

In tests, the database runs fully in memory (`NativeDatabase.memory()`); on a
device it is created in the application documents directory.

## Docker Development

The development environment is fully containerized. The image is based on a
maintained, stable Flutter + Android toolchain image and adds the build
dependencies the project needs.

```bash
make docker-build    # build the development image
make doctor          # confirm the toolchain is healthy inside the container
```

The container is used for:

- dependency management (`flutter pub get`)
- code generation (`build_runner`)
- static analysis, formatting, and tests
- release/debug **APK builds**

The Android emulator/device runs on the **host** — it is not run inside
Docker. The app container exposes no ports. The optional Funding server (see
[Donations / Funding](#donations--funding)) is a separate Dart service that
runs on the host or in its own deployment.

Persistent caches (named volumes survive image rebuilds):

- pub cache (`/root/.pub-cache`)
- Gradle cache (`/root/.gradle`)
- Android SDK additions
- build output and `.dart_tool` (shadowed so host and container never
  overwrite each other's tool state — each side keeps its own)

> **Note:** the container runs as `root`. Generated tool state is confined to
> the shadowed volumes above, so the bind-mounted source tree stays clean.
> Build the APK with `make build` when you need the artifact on the host;
> artifacts produced inside the container live in its named volume.

## Available Make Commands

```text
setup            Initialize the development environment (build image, deps, generate)
docker-build     Build the development image
up / down        Start / stop the container
doctor           Run Flutter/environment diagnostics
get              flutter pub get
generate         Run build_runner code generation
analyze          Static analysis
format           Format all Dart sources
format-check     Verify formatting
test             Run unit/widget tests
build            Build the release APK
build-debug      Build the debug APK
clean            flutter clean
shell            Open a shell inside the container
* -local         Same commands using a locally installed Flutter SDK
```

Run `make help` to list them with descriptions.

## Running Locally

Requires a locally installed Flutter SDK (stable) with an Android toolchain.

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run          # with a device/emulator attached
```

## Running With Docker

```bash
make docker-build
make setup
make shell           # interactive shell inside the dev container
flutter run          # from inside the shell, device attached on the host
```

Alternatively run the app on the host while using the container only for the
validation commands (as the Makefile intends).

## Testing

```bash
make test            # unit/widget tests (in-memory database, no network)
flutter test integration_test  # on-device integration tests (device required)
```

What is covered by the test foundation:

- application starts and renders the branding
- GoRouter navigation resolves required routes
- the database initializes, opens, persists, and enforces foreign keys
- Riverpod dependency injection wires `AppDatabase` and its DAOs
- the app shell performs no network I/O

## Building APK

```bash
make build           # release APK
make build-local     # or with a local SDK
```

Output: `build/app/outputs/flutter-apk/app-release.apk`.

## CI

`.github/workflows/flutter.yml` runs on every push/PR to `main`:

1. checkout
2. Flutter (stable) setup
3. dependency installation
4. code generation (`build_runner`)
5. formatting check
6. static analysis
7. unit/widget tests
8. debug APK build

The workflow fails on any analyzer error, test failure, formatting drift, or
build failure. Play Store deployment is intentionally out of scope for now.
On-device integration tests require an emulator/device and are therefore run
locally or in a future device-backed CI job.

## Development Guidelines

- Do not modify generated files (`*.g.dart`, `*.freezed.dart`); regenerate with
  `make generate`.
- Keep the dependency direction: Presentation → Domain → Data.
- Update `AppConstants.databaseSchemaVersion` and add migration steps whenever
  the schema changes. Never reset the database destructively.
- Use the error hierarchy in `core/errors` for consistent error handling.
- Use AppTheme tokens (`app_theme.dart`) instead of hardcoded styling.
- Do not store secrets anywhere in the repository.
- Run `make format-check analyze test` before pushing.

## Donations / Funding

The optional **Funding** feature lets a supporter make a small, thank-you
contribution. It is strictly online-only: the offline-first trip experience
never requires it.

- The funding **server** lives in [`server/`](server/README.md) — a minimal
  Dart backend with its own SQLite ledger and a headless (no Flutter) test
  suite.
- Amounts are **server-authoritative**: every funding type maps to a fixed
  price in integer minor units (paise) on the server, so a client can never
  charge itself a different price.
- Two local modes exist:
  - `GATEWAY_MODE=simulated` (default) — sandbox checkout via a server route,
    no credentials required.
  - `GATEWAY_MODE=razorpay` — real orders created server-side and a hosted
    **Razorpay Checkout** (`razorpay_flutter`) opened by the app.

### Razorpay integration

- Order creation happens **server-side** (`POST /api/v1/funding/orders`) using
  `RAZORPAY_KEY_ID` + `RAZORPAY_KEY_SECRET`. The response exposes only the
  public `keyId` (and the order's `orderId`) to the app.
- The app opens the hosted Checkout with `keyId`, `orderId`, amount (paise),
  currency, and the current order description.
- On Checkout success the app calls the `/verify` endpoint with the callback's
  `paymentId` and `signature`; the server HMAC-verifies the signature and
  confirms the order. This gives immediate confirmation.
- The **webhook** (`POST /api/v1/funding/webhooks/razorpay`) is the primary
  verification path in production: each payload is HMAC-SHA256 verified with
  `RAZORPAY_WEBHOOK_SECRET` and applied idempotently per Razorpay event id.
- The app **never marks a payment VERIFIED locally**. If the `/verify` leg is
  lost (network drop), the app navigates to the receipt screen, which re-fetches
  `GET /api/v1/funding/{ref}/status` for the authoritative state.
- To exercise Checkout against Razorpay test keys, set the webhook secret +
  URL in the Razorpay Dashboard (Settings → Webhooks):
  `POST {server}/api/v1/funding/webhooks/razorpay`, events `payment.captured`,
  `payment.failed`, `order.paid`, `order.cancelled`.

### Configuration

The server reads `server/.env` (see `server/.env.example`) for
`GATEWAY_MODE`, `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`,
`RAZORPAY_WEBHOOK_SECRET`, `FUNDING_ENV`, and the ledger path. The app needs
only `FUNDING_API_BASE_URL` at build time, and it already defaults to the
deployed production backend (`https://tripsplit-funding.onrender.com`), so any
build talks to the funding service out of the box. Override it to point at a
local sandbox or a different host:

```bash
flutter run --dart-define=FUNDING_API_BASE_URL=https://funding.example.com
```

**Security:** `RAZORPAY_KEY_SECRET` and `RAZORPAY_WEBHOOK_SECRET` are
server-only. They are never compiled into the Flutter app, stored in SQLite or
SharedPreferences, embedded in assets, or committed to the repository — the
client only ever receives the public `RAZORPAY_KEY_ID`.

## Future Backend Strategy

The core trip experience **does not require a backend**. The architecture is
prepared so a general backend can be introduced later, only when a real
external requirement exists, for:

- account synchronization
- multi-device synchronization
- shared trip collaboration

A future generic backend would sit behind the same repository interfaces used
today, so the domain and presentation layers would be unaffected. No general
account/sync/auth services are part of this phase — the only network service is
the scoped funding server described above.