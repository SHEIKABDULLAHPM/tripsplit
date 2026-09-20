/// SQL persistence for the funding ledger.
///
/// Uses a dedicated SQLite database (never the TripSplit offline database) so
/// funding records can never interfere with the expense ledger. All writes
/// that must be atomic run inside explicit transactions and unique constraints
/// back the idempotency guarantees.
library;

import 'package:sqlite3/sqlite3.dart';

import '../domain/funding_status.dart';
import '../domain/funding_type.dart';
import '../domain/models.dart';

/// Thrown when an operation violates a domain invariant or a unique
/// constraint.
class FundingStoreException implements Exception {
  final String code;
  final String message;

  const FundingStoreException(this.code, this.message);

  @override
  String toString() => 'FundingStoreException($code): $message';
}

/// Raised to surface a lost idempotency race without killing a connection.
class IdempotencyConflict implements Exception {
  const IdempotencyConflict();
}

/// Data-access layer for funding records.
class FundingStore {
  Database? _db;

  FundingStore._(Database db) : _db = db;

  /// Opens (and migrates) a store persisted at [path].
  factory FundingStore.open(String path) {
    final db = sqlite3.open(path);
    db.execute('PRAGMA journal_mode = WAL;');
    db.execute('PRAGMA foreign_keys = ON;');
    db.execute('PRAGMA busy_timeout = 3000;');
    final store = FundingStore._(db);
    store._migrate();
    return store;
  }

  /// Opens an in-memory store (used by tests).
  factory FundingStore.openInMemory() {
    final db = sqlite3.openInMemory();
    db.execute('PRAGMA foreign_keys = ON;');
    final store = FundingStore._(db);
    store._migrate();
    return store;
  }

  void _migrate() {
    _db!.execute('''
      CREATE TABLE IF NOT EXISTS funding_orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        public_reference TEXT NOT NULL UNIQUE,
        idempotency_key TEXT,
        funding_type TEXT NOT NULL CHECK (funding_type IN ('SUPPORT_49','FUTURE_199')),
        amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
        currency TEXT NOT NULL CHECK (currency = 'INR'),
        status TEXT NOT NULL,
        terms_version TEXT NOT NULL,
        accepted_at TEXT NOT NULL,
        client_ip TEXT,
        gateway_order_id TEXT UNIQUE,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        verified_at TEXT
      );
      CREATE UNIQUE INDEX IF NOT EXISTS ux_funding_orders_idem
        ON funding_orders(idempotency_key)
        WHERE idempotency_key IS NOT NULL;
      CREATE INDEX IF NOT EXISTS ix_funding_orders_status
        ON funding_orders(status);

      CREATE TABLE IF NOT EXISTS funding_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        funding_order_id INTEGER NOT NULL REFERENCES funding_orders(id),
        gateway_payment_id TEXT NOT NULL UNIQUE,
        gateway_order_id TEXT NOT NULL,
        amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
        currency TEXT NOT NULL CHECK (currency = 'INR'),
        status TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        verified_at TEXT
      );
      CREATE UNIQUE INDEX IF NOT EXISTS ux_funding_pay_gworder
        ON funding_payments(gateway_order_id);

      CREATE TABLE IF NOT EXISTS funding_webhook_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        gateway_event_id TEXT NOT NULL UNIQUE,
        event_type TEXT NOT NULL,
        gateway_payment_id TEXT NOT NULL,
        payload_hash TEXT NOT NULL,
        processed INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS reconciliation_runs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        started_at TEXT NOT NULL,
        finished_at TEXT,
        mismatches INTEGER NOT NULL DEFAULT 0,
        detail TEXT
      );
    ''');
  }

  void close() {
    _db?.close();
    _db = null;
  }

  /// Runs [action] inside a BEGIN IMMEDIATE..COMMIT transaction, rolling back
  /// on any error.
  T _inTransaction<T>(T Function(Database db) action) {
    final db = _db!;
    db.execute('BEGIN IMMEDIATE');
    try {
      final result = action(db);
      db.execute('COMMIT');
      return result;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  // ---------------------------------------------------------------- helpers

  FundingOrder _rowToOrder(Row row) => FundingOrder(
    publicReference: row['public_reference'] as String,
    fundingType: FundingType.fromWire(row['funding_type'] as String)!,
    amountMinor: row['amount_minor'] as int,
    currency: row['currency'] as String,
    status: FundingStatus.fromWire(row['status'] as String)!,
    termsVersion: row['terms_version'] as String,
    clientIp: row['client_ip'] as String?,
    createdAt: row['created_at'] as String,
    acceptedAt: row['accepted_at'] as String,
    gatewayOrderId: row['gateway_order_id'] as String?,
    idempotencyKey: row['idempotency_key'] as String?,
    updatedAt: row['updated_at'] as String,
    verifiedAt: row['verified_at'] as String?,
  );

  _PaymentRow _rowToPayment(Row row) => _PaymentRow(
    id: row['id'] as int,
    gatewayPaymentId: row['gateway_payment_id'] as String,
    gatewayOrderId: row['gateway_order_id'] as String,
    amountMinor: row['amount_minor'] as int,
    currency: row['currency'] as String,
    status: PaymentStatus.fromWire(row['status'] as String)!,
    createdAt: row['created_at'] as String,
    verifiedAt: row['verified_at'] as String?,
  );

  int _orderRowId(String publicReference) {
    final rows = _db!.select(
      'SELECT id FROM funding_orders WHERE public_reference = ?',
      [publicReference],
    );
    if (rows.isEmpty) {
      throw FundingStoreException('order_not_found', 'Unknown order reference');
    }
    return rows.first['id'] as int;
  }

  // ----------------------------------------------------------------- orders

  /// Creates a funding order, returning it.
  ///
  /// When [idempotencyKey] is provided, an existing order for the same key is
  /// returned instead of creating a duplicate. If the existing order was
  /// created for a different funding type, [IdempotencyConflict] is raised.
  FundingOrder createOrder({
    required String publicReference,
    required FundingType fundingType,
    required String termsVersion,
    required String acceptedAt,
    required String now,
    String? idempotencyKey,
    String? clientIp,
  }) {
    if (idempotencyKey != null) {
      final existing = findByIdempotencyKey(idempotencyKey);
      if (existing != null) {
        if (existing.fundingType != fundingType) {
          throw const IdempotencyConflict();
        }
        return existing;
      }
    }
    try {
      _db!.execute(
        '''
        INSERT INTO funding_orders (
          public_reference, idempotency_key, funding_type, amount_minor,
          currency, status, terms_version, accepted_at, client_ip,
          created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          publicReference,
          idempotencyKey,
          fundingType.wire,
          fundingType.amountMinor,
          fundingType.currency,
          FundingStatus.created.wire,
          termsVersion,
          acceptedAt,
          clientIp,
          now,
          now,
        ],
      );
    } on SqliteException catch (e) {
      if (e.extendedResultCode == 2067) {
        // SQLITE_CONSTRAINT_UNIQUE — lost a race against another request with
        // the same idempotency key or reference.
        throw const IdempotencyConflict();
      }
      rethrow;
    }
    return (findByIdempotencyKey(idempotencyKey) ??
        findByReference(publicReference))!;
  }

  FundingOrder? findByIdempotencyKey(String? key) {
    if (key == null) return null;
    final rows = _db!.select(
      'SELECT * FROM funding_orders WHERE idempotency_key = ?',
      [key],
    );
    if (rows.isEmpty) return null;
    return _rowToOrder(rows.first);
  }

  FundingOrder? findByReference(String publicReference) {
    final rows = _db!.select(
      'SELECT * FROM funding_orders WHERE public_reference = ?',
      [publicReference],
    );
    if (rows.isEmpty) return null;
    return _rowToOrder(rows.first);
  }

  FundingOrder? findByGatewayOrderId(String gatewayOrderId) {
    final rows = _db!.select(
      'SELECT * FROM funding_orders WHERE gateway_order_id = ?',
      [gatewayOrderId],
    );
    if (rows.isEmpty) return null;
    return _rowToOrder(rows.first);
  }

  List<FundingOrder> listOrders({FundingStatus? status}) {
    final rows = status == null
        ? _db!.select('SELECT * FROM funding_orders ORDER BY id DESC')
        : _db!.select(
            'SELECT * FROM funding_orders WHERE status = ? ORDER BY id DESC',
            [status.wire],
          );
    return rows.map(_rowToOrder).toList();
  }

  /// Applies a state transition. Returns the updated order, or null when the
  /// transition is not legal.
  FundingOrder? transitionOrder(
    String publicReference, {
    required FundingStatus to,
    required String now,
    String? gatewayOrderId,
    String? verifiedAt,
  }) {
    return _inTransaction((db) {
      final current = findByReference(publicReference);
      if (current == null) return null;
      if (!current.status.canTransitionTo(to)) return null;
      db.execute(
        '''
        UPDATE funding_orders
        SET status = ?,
            gateway_order_id = COALESCE(gateway_order_id, ?),
            verified_at = COALESCE(?, verified_at),
            updated_at = ?
        WHERE public_reference = ?
        ''',
        [to.wire, gatewayOrderId, verifiedAt, now, publicReference],
      );
      return findByReference(publicReference);
    });
  }

  // -------------------------------------------------------------- payments

  FundingPayment insertPayment({
    required String fundingOrderPublicRef,
    required String gatewayPaymentId,
    required String gatewayOrderId,
    required int amountMinor,
    required String currency,
    required PaymentStatus status,
    required String now,
  }) {
    try {
      _db!.execute(
        '''
        INSERT INTO funding_payments (
          funding_order_id, gateway_payment_id, gateway_order_id,
          amount_minor, currency, status, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          _orderRowId(fundingOrderPublicRef),
          gatewayPaymentId,
          gatewayOrderId,
          amountMinor,
          currency,
          status.wire,
          now,
          now,
        ],
      );
    } on SqliteException catch (e) {
      if (e.extendedResultCode == 2067) {
        return findPaymentByGatewayId(gatewayPaymentId)!;
      }
      rethrow;
    }
    return findPaymentByGatewayId(gatewayPaymentId)!;
  }

  FundingPayment? findPaymentByGatewayId(String gatewayPaymentId) {
    final rows = _db!.select(
      'SELECT * FROM funding_payments WHERE gateway_payment_id = ?',
      [gatewayPaymentId],
    );
    if (rows.isEmpty) return null;
    return _paymentForRow(rows.first);
  }

  /// Returns a payment already recorded for a gateway order, regardless of the
  /// gateway payment id. The client-side verification leg records a PENDING
  /// payment under the order before the webhook delivers the real gateway
  /// payment id, so confirmation must update — never duplicate — that row.
  FundingPayment? _paymentByGatewayOrder(String gatewayOrderId) {
    final rows = _db!.select(
      'SELECT * FROM funding_payments WHERE gateway_order_id = ?',
      [gatewayOrderId],
    );
    if (rows.isEmpty) return null;
    return _paymentForRow(rows.first);
  }

  FundingPayment _paymentForRow(Row row) {
    final payment = _rowToPayment(row);
    final orderRows = _db!.select(
      'SELECT public_reference FROM funding_orders WHERE id = ?',
      [row['id'] as int],
    );
    return FundingPayment(
      id: payment.id,
      fundingOrderPublicRef: orderRows.isEmpty
          ? ''
          : orderRows.first['public_reference'] as String,
      gatewayPaymentId: payment.gatewayPaymentId,
      gatewayOrderId: payment.gatewayOrderId,
      amountMinor: payment.amountMinor,
      currency: payment.currency,
      status: payment.status,
      createdAt: payment.createdAt,
      verifiedAt: payment.verifiedAt,
    );
  }

  List<FundingPayment> listPaymentsForOrder(String publicReference) {
    final orderId = _orderRowId(publicReference);
    final rows = _db!.select(
      'SELECT * FROM funding_payments WHERE funding_order_id = ? ORDER BY id',
      [orderId],
    );
    return rows.map((row) => _paymentForRow(row)).toList(growable: false);
  }

  void updateExistingPaymentStatus(
    String gatewayPaymentId,
    PaymentStatus status,
    String now,
  ) {
    _db!.execute(
      '''
      UPDATE funding_payments
      SET status = ?, updated_at = ?, verified_at = COALESCE(?, verified_at)
      WHERE gateway_payment_id = ?
      ''',
      [
        status.wire,
        now,
        status == PaymentStatus.verified ? now : null,
        gatewayPaymentId,
      ],
    );
  }

  // ------------------------------------------------------ webhook dedupe

  /// Records an inbound webhook event. Returns false when the event was
  /// already recorded (idempotent replay).
  bool recordWebhookEvent({
    required String gatewayEventId,
    required String eventType,
    required String gatewayPaymentId,
    required String payloadHash,
    required String now,
  }) {
    try {
      _db!.execute(
        '''
        INSERT INTO funding_webhook_events (
          gateway_event_id, event_type, gateway_payment_id,
          payload_hash, created_at
        ) VALUES (?, ?, ?, ?, ?)
        ''',
        [gatewayEventId, eventType, gatewayPaymentId, payloadHash, now],
      );
      return true;
    } on SqliteException catch (e) {
      if (e.extendedResultCode == 2067) {
        return false;
      }
      rethrow;
    }
  }

  bool isWebhookEventProcessed(String gatewayEventId) {
    final rows = _db!.select(
      'SELECT processed FROM funding_webhook_events WHERE gateway_event_id = ?',
      [gatewayEventId],
    );
    if (rows.isEmpty) return false;
    return (rows.first['processed'] as int) == 1;
  }

  void markWebhookEventProcessed(String gatewayEventId) {
    _db!.execute(
      'UPDATE funding_webhook_events SET processed = 1 WHERE gateway_event_id = ?',
      [gatewayEventId],
    );
  }

  // -------------------------------------------------------- reconciliation

  /// Returns every order plus its gateway payment. Used by the reconciliation
  /// handler to compare against the gateway ledger.
  List<({FundingOrder order, FundingPayment? payment})>
  allOrdersWithPayments() {
    final orders = listOrders();
    return [
      for (final order in orders)
        (
          order: order,
          payment: listPaymentsForOrder(order.publicReference).firstOrNull,
        ),
    ];
  }

  void recordReconciliationRun({
    required String startedAt,
    String? finishedAt,
    required int mismatches,
    String? detail,
  }) {
    _db!.execute(
      '''
      INSERT INTO reconciliation_runs (started_at, finished_at, mismatches, detail)
      VALUES (?, ?, ?, ?)
      ''',
      [startedAt, finishedAt, mismatches, detail],
    );
  }

  // ---------------------------------------------------------- verification

  /// Gateway-authoritative status change.
  ///
  /// The display state machine [transitionOrder] governs the normal checkout
  /// lifecycle, but a gateway can confirm (or refuse) money at any point.
  /// This applies the real-world truth directly, while refusing to un-verify
  /// an order that was already verified or refunded.
  FundingOrder? _forceSetStatus(
    String publicReference,
    FundingStatus to,
    String now,
  ) {
    final current = findByReference(publicReference);
    if (current == null) return null;
    if (current.status == to) return current;
    if (current.status == FundingStatus.verified ||
        current.status == FundingStatus.refunded) {
      return current;
    }
    if (to == FundingStatus.verified &&
        (current.status == FundingStatus.failed ||
            current.status == FundingStatus.cancelled ||
            current.status == FundingStatus.expired)) {
      return current;
    }
    _db!.execute(
      '''
      UPDATE funding_orders
      SET status = ?,
          verified_at = COALESCE(?, verified_at),
          updated_at = ?
      WHERE public_reference = ?
      ''',
      [
        to.wire,
        to == FundingStatus.verified ? now : null,
        now,
        publicReference,
      ],
    );
    return findByReference(publicReference);
  }

  /// The single atomic path by which real money is deemed received.
  ///
  /// Ensures the gateway-reported amount and currency match the order, the
  /// payment is recorded exactly once per gateway id, and both order and
  /// payment land in VERIFIED simultaneously. Idempotent: a second invocation
  /// for an already-verified payment is a no-op.
  String? verifyPayment({
    required String gatewayOrderId,
    required String gatewayPaymentId,
    required int amountMinor,
    required String currency,
    required String now,
  }) {
    final order = findByGatewayOrderId(gatewayOrderId);
    if (order == null) {
      throw FundingStoreException(
        'unknown_gateway_order',
        'No order for this gateway order id',
      );
    }
    if (order.amountMinor != amountMinor || order.currency != currency) {
      throw FundingStoreException(
        'amount_mismatch',
        'Gateway reported amount does not match the order',
      );
    }
    return _inTransaction((db) {
      final existing = findPaymentByGatewayId(gatewayPaymentId);
      if (existing != null) {
        if (existing.amountMinor != amountMinor ||
            existing.currency != currency) {
          throw FundingStoreException(
            'amount_mismatch',
            'Gateway payment amount does not match the recorded payment',
          );
        }
        if (existing.status == PaymentStatus.verified &&
            order.status == FundingStatus.verified) {
          return order.publicReference; // idempotent replay
        }
        updateExistingPaymentStatus(
          gatewayPaymentId,
          PaymentStatus.verified,
          now,
        );
      } else {
        // A payment may already be recorded for this gateway order but under a
        // different gateway payment id (the client-side verification leg marked
        // it PENDING first). Confirm it instead of inserting a duplicate row.
        final byOrder = _paymentByGatewayOrder(gatewayOrderId);
        if (byOrder != null) {
          if (byOrder.amountMinor != amountMinor ||
              byOrder.currency != currency) {
            throw FundingStoreException(
              'amount_mismatch',
              'Gateway payment amount does not match the recorded payment',
            );
          }
          if (byOrder.gatewayPaymentId != gatewayPaymentId &&
              gatewayPaymentId.isNotEmpty) {
            _db!.execute(
              '''
              UPDATE funding_payments
              SET gateway_payment_id = ?,
                  status = ?,
                  updated_at = ?,
                  verified_at = ?
              WHERE id = ?
              ''',
              [
                gatewayPaymentId,
                PaymentStatus.verified.wire,
                now,
                now,
                byOrder.id,
              ],
            );
          } else {
            updateExistingPaymentStatus(
              byOrder.gatewayPaymentId,
              PaymentStatus.verified,
              now,
            );
          }
        } else {
          insertPayment(
            fundingOrderPublicRef: order.publicReference,
            gatewayPaymentId: gatewayPaymentId,
            gatewayOrderId: gatewayOrderId,
            amountMinor: amountMinor,
            currency: currency,
            status: PaymentStatus.verified,
            now: now,
          );
        }
      }
      _forceSetStatus(order.publicReference, FundingStatus.verified, now);
      return order.publicReference;
    });
  }

  /// Marks a payment and its order as failed (gateway reported a failure).
  /// Never revokes a verified or refunded order.
  String? failPayment({
    required String gatewayOrderId,
    required String gatewayPaymentId,
    required String now,
  }) {
    final order = findByGatewayOrderId(gatewayOrderId);
    if (order == null) return null;
    return _inTransaction((db) {
      final existing = findPaymentByGatewayId(gatewayPaymentId);
      if (existing != null) {
        updateExistingPaymentStatus(
          gatewayPaymentId,
          PaymentStatus.failed,
          now,
        );
      } else {
        final byOrder = _paymentByGatewayOrder(gatewayOrderId);
        if (byOrder != null) {
          // Never downgrade an already-verified payment; a stray failure event
          // must not revoke confirmed money.
          if (byOrder.status != PaymentStatus.verified) {
            updateExistingPaymentStatus(
              byOrder.gatewayPaymentId,
              PaymentStatus.failed,
              now,
            );
          }
        } else {
          insertPayment(
            fundingOrderPublicRef: order.publicReference,
            gatewayPaymentId: gatewayPaymentId,
            gatewayOrderId: gatewayOrderId,
            amountMinor: order.amountMinor,
            currency: order.currency,
            status: PaymentStatus.failed,
            now: now,
          );
        }
      }
      _forceSetStatus(order.publicReference, FundingStatus.failed, now);
      return order.publicReference;
    });
  }
}

/// Thin mutable holder used while converting a SQL row into a payment.
class _PaymentRow {
  final int id;
  final String gatewayPaymentId;
  final String gatewayOrderId;
  final int amountMinor;
  final String currency;
  final PaymentStatus status;
  final String createdAt;
  final String? verifiedAt;

  const _PaymentRow({
    required this.id,
    required this.gatewayPaymentId,
    required this.gatewayOrderId,
    required this.amountMinor,
    required this.currency,
    required this.status,
    required this.createdAt,
    this.verifiedAt,
  });
}

extension on List<FundingPayment> {
  FundingPayment? get firstOrNull => isEmpty ? null : first;
}
