# TripSplit Funding Server

A minimal, dependency-light funding backend for TripSplit. It creates funding
orders with server-authoritative amounts, verifies payment webhooks with HMAC
signatures, and maintains an idempotent funding ledger in its own SQLite
database — completely separate from any TripSplit offline trip data.

## Run (sandbox, no credentials)

```bash
dart pub get --offline
GATEWAY_MODE=simulated dart run bin/server.dart
```

Then ping the health endpoint: `curl http://localhost:8080/health`.

## Configuration (environment + `.env`)

Secrets are managed through a git-ignored `.env` file in this directory
(see [`.env.example`](.env.example)) and **never** through the repository,
the Flutter app, or any HTTP response. The loader merges `.env` values as
defaults — real environment variables (Docker/K8s secrets, CI, production
hosts) always win.

```bash
cp .env.example .env   # then fill in real values
GATEWAY_MODE=razorpay dart run bin/server.dart
```

| Variable                 | Default                         | Note                                    |
| ------------------------ | ------------------------------- | --------------------------------------- |
| `PORT`                   | `8080`                          | Bind port                               |
| `FUNDING_DB_PATH`        | `funding.sqlite3`               | Funding ledger database (alias: `DATABASE_URL`) |
| `DATABASE_URL`           | –                               | SQLite path / `file:` URL (server-only) |
| `FUNDING_ENV`            | `test`                          | `development` / `staging` / `production` / `test` (`test` adds dev CORS) |
| `GATEWAY_MODE`           | `simulated`                     | `simulated` (sandbox) or `razorpay`      |
| `RAZORPAY_KEY_ID`        | –                               | Public key id (served to the app at order creation) |
| `RAZORPAY_KEY_SECRET`    | –                               | Server-only secret — never leaves the server |
| `RAZORPAY_WEBHOOK_SECRET`| –                               | Dashboard webhook secret (HMAC verification) |
| `RAZORPAY_API_BASE`      | `https://api.razorpay.com`      | Override for proxies/mocks               |
| `FUNDING_WEBHOOK_SECRET` | dev-only default (simulated)    | Legacy alias for `RAZORPAY_WEBHOOK_SECRET` |
| `FUNDING_ADMIN_KEY`      | unset                           | Enables `reconciliation` (admin-only)    |
| `CURRENT_TERMS_VERSION`  | `2026-09-01`                    | Version shown/accepted per order         |
| `FUNDING_PUBLIC_BASE_URL`| `http://localhost:8080`         | Public base used for links               |
| `MAX_BODY_BYTES`         | `1048576` (1 MiB)               | Request body cap                         |

### Environment separation

- **Development / Staging** — `FUNDING_ENV=development|staging`, `GATEWAY_MODE=razorpay`, and the Razorpay **test** key pair (`rzp_test_…`); no live credentials ever appear here.
- **Production** — `FUNDING_ENV=production`, `GATEWAY_MODE=razorpay`, the Razorpay **live** key pair, and secrets injected through the platform (never a committed file).
- Only the public `RAZORPAY_KEY_ID` is returned to the app (inside the order-creation response); the Key Secret and webhook secret are never exposed.

## Endpoints

| Method | Path                                          | Purpose                                    |
| ------ | --------------------------------------------- | ------------------------------------------ |
| GET    | `/health`                                     | Liveness, env, gateway, terms version       |
| POST   | `/api/v1/funding/orders`                      | Create an order (terms acceptance required) |
| POST   | `/api/v1/funding/<ref>/verify`                | Verify a Checkout success signature (immediate confirmation) |
| GET    | `/api/v1/funding/<ref>/status`                | Order status (sanitized)                   |
| POST   | `/api/v1/funding/webhooks/razorpay`           | Signed webhook delivery (HMAC verified)    |
| POST   | `/api/v1/funding/simulator/checkout/<ref>`    | Sandbox-only checkout emulation (simulated mode) |
| GET    | `/api/v1/funding/terms[?version=]`            | Current/requested terms bundle             |
| GET    | `/api/v1/funding/history`                     | Sanitized order history                    |
| GET    | `/api/v1/funding/reconciliation`              | Ledger vs gateway (requires `X-Admin-Key`) |

## Security properties

- Amount and currency are always taken from the server (`FundingType` enum in
  paise) — a client can never charge itself a different price.
- Razorpay orders are created server-side with the Key Secret; the Checkout
  success signature (`order_id|payment_id` HMAC) and webhook payloads are both
  verified server-side (Key Secret / webhook secret respectively).
- Webhook payloads are verified with HMAC-SHA256 over the raw body; every real
  path to "verified" runs through `processWebhook`.
- Duplicate detection via unique constraints on `gateway_event_id`,
  `gateway_payment_id`, `gateway_order_id`, and `idempotency_key`.
- Verification is atomic — payment and order land in `VERIFIED` in one
  transaction; the amount/currency cross-check happens inside it.
- Client responses never contain the Key Secret, webhook secret, payment ids,
  or signatures; internal detail is only ever written to the structured audit
  log.
- The Razorpay Key Secret is never compiled into the Flutter app, stored in
  SQLite/SharedPreferences, embedded in assets, or committed to the repository.

## Tests

```bash
dart test
```

Tests cover order creation, both funding types, idempotent double-taps,
signature rejection, amount/currency forgery, lifecycle end-to-end, history
sanitization, reconciliation, rate limiting, payload caps, and the Razorpay
adapter (webhook HMAC, client-signature verification, event parsing, order
creation) against an in-memory HTTP mock.

## Gateway adapters

`PaymentGateway` is implemented by:

- `SimulatedGateway` — sandbox transport used by `GATEWAY_MODE=simulated`
  (default, no credentials). Exposes the checkout-simulator route.
- `RazorpayGateway` — production adapter used by `GATEWAY_MODE=razorpay`.
  Creates server-side orders, verifies Checkout signatures, and validates
  webhooks. The simulator route is disabled.

The checkout-simulator route is served only in `GATEWAY_MODE=simulated`, so
production builds are never exposed.

## LEGAL REVIEW REQUIRED

All legal copy in `lib/config/legal_copy.dart` is a **DRAFT placeholder**. The
documents are clearly marked `draft: true` and must be reviewed/replaced by a
qualified legal professional before the feature processes real money. The
issuer, jurisdiction, contact, and effective-version fields are centralized
data — updating them is a configuration change, not a code change.