/// Lifecycle of a funding order.
///
/// Only the transitions listed in [canTransitionTo] are legal. The state
/// machine is enforced in the repository so a malformed (or tampered) caller
/// can never jump the ledger to a terminal state without going through the
/// gateway change detector.
library;

/// Statuses a funding order can be in.
///
/// Order intentionally kept matching the requirement document:
/// CREATED, CHECKOUT_STARTED, PAYMENT_PENDING, AUTHORIZED, CAPTURED,
/// VERIFICATION_PENDING, VERIFIED, FAILED, CANCELLED, EXPIRED, REFUNDED.
enum FundingStatus {
  created('CREATED'),
  checkoutStarted('CHECKOUT_STARTED'),
  paymentPending('PAYMENT_PENDING'),
  authorized('AUTHORIZED'),
  captured('CAPTURED'),
  verificationPending('VERIFICATION_PENDING'),
  verified('VERIFIED'),
  failed('FAILED'),
  cancelled('CANCELLED'),
  expired('EXPIRED'),
  refunded('REFUNDED');

  final String wire;

  const FundingStatus(this.wire);

  static FundingStatus? fromWire(String? value) {
    for (final status in values) {
      if (status.wire == value) return status;
    }
    return null;
  }

  /// True when the order reached a terminal state.
  bool get isTerminal => switch (this) {
    verified || failed || cancelled || expired || refunded => true,
    _ => false,
  };

  /// True when money has actually been received and remains held.
  bool get isPaid => this == verified || this == refunded;

  bool canTransitionTo(FundingStatus next) =>
      FinancialStateTransition.canTransition(this, next);
}

/// Ordered step of the original requirement document — used only to compute
/// lane transitions deterministically.
enum FinancialStateTransition {
  created,
  checkoutStarted,
  paymentPending,
  authorized,
  captured,
  verificationPending,
  verified,
  failed,
  cancelled,
  expired,
  refunded;

  static bool canTransition(FundingStatus from, FundingStatus to) {
    if (from == to) return true;
    if (from.isTerminal) return false;
    return switch (from) {
      FundingStatus.created => switch (to) {
        FundingStatus.checkoutStarted ||
        FundingStatus.paymentPending ||
        FundingStatus.cancelled ||
        FundingStatus.expired ||
        FundingStatus.failed => true,
        _ => false,
      },
      FundingStatus.checkoutStarted => switch (to) {
        FundingStatus.paymentPending ||
        FundingStatus.authorized ||
        FundingStatus.cancelled ||
        FundingStatus.expired ||
        FundingStatus.failed => true,
        _ => false,
      },
      FundingStatus.paymentPending => switch (to) {
        FundingStatus.authorized ||
        FundingStatus.verificationPending ||
        FundingStatus.failed ||
        FundingStatus.expired ||
        FundingStatus.cancelled => true,
        _ => false,
      },
      FundingStatus.authorized => switch (to) {
        FundingStatus.captured ||
        FundingStatus.verificationPending ||
        FundingStatus.failed ||
        FundingStatus.refunded ||
        FundingStatus.expired => true,
        _ => false,
      },
      FundingStatus.captured => switch (to) {
        FundingStatus.verificationPending || FundingStatus.verified => true,
        _ => false,
      },
      FundingStatus.verificationPending => switch (to) {
        FundingStatus.verified || FundingStatus.failed => true,
        _ => false,
      },
      _ => false,
    };
  }
}

/// Statuses for a single payment within an order (gateway payment object).
enum PaymentStatus {
  pending('PENDING'),
  authorized('AUTHORIZED'),
  captured('CAPTURED'),
  verified('VERIFIED'),
  failed('FAILED'),
  refunded('REFUNDED');

  final String wire;

  const PaymentStatus(this.wire);

  static PaymentStatus? fromWire(String? value) {
    for (final status in values) {
      if (status.wire == value) return status;
    }
    return null;
  }
}
