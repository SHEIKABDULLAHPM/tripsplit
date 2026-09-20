/// Hosted payment-gateway checkout launcher abstraction.
///
/// The real implementation wraps the razorpay_flutter plugin; tests inject a
/// fake so no plugin and no real payment are ever touched in widget tests.
library;

/// Everything the hosted checkout needs for a single order.
class RazorpayCheckoutRequest {
  const RazorpayCheckoutRequest({
    required this.keyId,
    required this.orderId,
    required this.amountMinor,
    required this.currency,
    required this.orderReference,
  });

  /// Public gateway key id — never a secret.
  final String keyId;

  /// Gateway order id created by the server.
  final String orderId;

  /// Amount in minor units (paise), server-authoritative.
  final int amountMinor;

  final String currency;

  /// Server public reference used for navigation after the checkout.
  final String orderReference;
}

/// A successful checkout: the gateway payment id, the gateway order id, and
/// the payment signature the server must verify before recording money.
typedef RazorpayOnSuccess =
    void Function(String paymentId, String orderId, String signature);

/// A failed or cancelled checkout ([code] matches the gateway's error codes).
typedef RazorpayOnError = void Function(int? code, String message);

/// Called when the user opted to pay through an external wallet.
typedef RazorpayOnExternalWallet = void Function(String walletName);

/// Launches the hosted checkout sheet for a single order.
///
/// Implementations must invoke exactly one of [onSuccess], [onError], or
/// [onExternalWallet] in response to [open]. [clear] releases any platform
/// resources the checkout holds.
abstract interface class RazorpayCheckoutLauncher {
  void open(
    RazorpayCheckoutRequest request, {
    required RazorpayOnSuccess onSuccess,
    required RazorpayOnError onError,
    required RazorpayOnExternalWallet onExternalWallet,
  });

  void clear();
}
