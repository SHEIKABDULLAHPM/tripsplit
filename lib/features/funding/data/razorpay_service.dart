import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../domain/funding_exception.dart';
import '../domain/razorpay_checkout.dart';

/// Real [RazorpayCheckoutLauncher] backed by the razorpay_flutter plugin.
///
/// The plugin only ever receives the public key id, the order id, the amount,
/// and the currency — the key secret lives solely on the funding server and
/// never reaches the app.
class RazorpayService implements RazorpayCheckoutLauncher {
  RazorpayService({Razorpay? razorpay}) : _razorpay = razorpay ?? Razorpay();

  final Razorpay _razorpay;

  @override
  void open(
    RazorpayCheckoutRequest request, {
    required RazorpayOnSuccess onSuccess,
    required RazorpayOnError onError,
    required RazorpayOnExternalWallet onExternalWallet,
  }) {
    fundingLog('Opening Razorpay Checkout: orderId=${request.orderId} '
        'amount=${request.amountMinor} currency=${request.currency}');
    _razorpay.clear();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (
      PaymentSuccessResponse response,
    ) {
      fundingLog('Razorpay payment success: paymentId=${response.paymentId}');
      onSuccess(
        response.paymentId ?? '',
        response.orderId ?? '',
        response.signature ?? '',
      );
    });
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (
      PaymentFailureResponse response,
    ) {
      fundingLogError(
        'Razorpay payment error: code=${response.code} '
        'message=${response.message}',
      );
      onError(
        response.code,
        response.message ?? 'Payment could not be completed.',
      );
    });
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (
      ExternalWalletResponse response,
    ) {
      fundingLog('Razorpay external wallet: ${response.walletName}');
      onExternalWallet(response.walletName ?? '');
    });
    _razorpay.open({
      'key': request.keyId,
      'order_id': request.orderId,
      'amount': request.amountMinor,
      'currency': request.currency,
      'name': 'TripSplit',
      'description': 'Funding order ${request.orderReference}',
    });
  }

  @override
  void clear() {
    fundingLog('Clearing Razorpay listeners');
    _razorpay.clear();
  }
}
