import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tripsplit/features/funding/data/connectivity_checker.dart';
import 'package:tripsplit/features/funding/data/funding_api_client.dart';
import 'package:tripsplit/features/funding/data/funding_repository.dart';
import 'package:tripsplit/features/funding/domain/funding_exception.dart';
import 'package:tripsplit/features/funding/domain/funding_info.dart';
import 'package:tripsplit/features/funding/domain/razorpay_checkout.dart';
import 'package:tripsplit/features/funding/presentation/funding_checkout_screen.dart';
import 'package:tripsplit/features/funding/presentation/funding_history_screen.dart';
import 'package:tripsplit/features/funding/presentation/funding_result_screen.dart';
import 'package:tripsplit/features/funding/presentation/funding_screen.dart';
import 'package:tripsplit/features/funding/providers/funding_providers.dart';

/// In-memory repository double. Never touches the network or any database.
class _FakeFundingRepository extends FundingRepository {
  _FakeFundingRepository()
    : super(FundingApiClient(baseUrl: 'http://funding-test.invalid'));

  final List<String> createdTypes = [];
  final List<String> simulated = [];
  final List<String> statusFetches = [];
  final List<({String ref, String orderId, String paymentId, String signature})>
  verifyCalls = [];
  List<FundingOrder> history = [];
  FundingOrder? createResult;
  FundingOrder? simulateResult;
  FundingOrder? statusResult;
  FundingOrder? verifyResult;
  FundingException? createError;
  FundingException? statusError;
  FundingException? verifyError;

  @override
  Future<FundingOrder> createOrder(
    FundingType type, {
    required String idempotencyKey,
    String? termsVersion,
  }) async {
    createdTypes.add(type.wire);
    if (createError != null) throw createError!;
    return createResult ??
        FundingOrder(
          publicReference: 'TS_4242',
          type: type,
          amountMinor: type == FundingType.future199 ? 19900 : 4900,
          currency: 'INR',
          status: FundingStatus.created,
          termsVersion: termsVersion ?? '2026-09-01',
          checkoutMode: 'simulated',
        );
  }

  @override
  Future<FundingOrder> simulateCheckout(
    String publicReference,
    String outcome,
  ) async {
    simulated.add('$publicReference:$outcome');
    return simulateResult ??
        FundingOrder(
          publicReference: publicReference,
          type: FundingType.support49,
          amountMinor: 4900,
          currency: 'INR',
          status: outcome == 'success'
              ? FundingStatus.verified
              : FundingStatus.failed,
          termsVersion: '2026-09-01',
          checkoutMode: 'simulated',
          verifiedAt: outcome == 'success' ? '2026-09-01T10:00:00Z' : null,
        );
  }

  @override
  Future<FundingOrder> fetchStatus(String publicReference) async {
    statusFetches.add(publicReference);
    if (statusError != null) throw statusError!;
    return statusResult ??
        FundingOrder(
          publicReference: publicReference,
          type: FundingType.support49,
          amountMinor: 4900,
          currency: 'INR',
          status: FundingStatus.verified,
          termsVersion: '2026-09-01',
          checkoutMode: 'simulated',
          verifiedAt: '2026-09-01T10:00:00Z',
        );
  }

  @override
  Future<FundingOrder> verifyPayment({
    required String publicReference,
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    verifyCalls.add((
      ref: publicReference,
      orderId: orderId,
      paymentId: paymentId,
      signature: signature,
    ));
    if (verifyError != null) throw verifyError!;
    return verifyResult ??
        FundingOrder(
          publicReference: publicReference,
          type: FundingType.support49,
          amountMinor: 4900,
          currency: 'INR',
          status: FundingStatus.paymentPending,
          termsVersion: '2026-09-01',
          checkoutMode: 'hosted',
        );
  }

  @override
  Future<List<FundingOrder>> fetchHistory() async => history;
}

/// Fake connectivity checker that always reports connected.
/// Never touches platform channels — safe for widget tests.
class _FakeConnectedChecker implements ConnectivityChecker {
  @override
  Future<bool> hasConnection() async => true;
}

/// Fake API client that passes connectivity checks without network access.
class _FakeFundingApiClient extends FundingApiClient {
  _FakeFundingApiClient() : super(baseUrl: 'http://funding-test.invalid');

  @override
  Future<bool> checkConnectivity() async => true;
}

/// Harness for the hosted-checkout launcher. Never touches the plugin.
class _RecordingCheckoutLauncher implements RazorpayCheckoutLauncher {
  final List<RazorpayCheckoutRequest> opened = [];

  /// When false, `open` reports failure (like the user cancelling).
  bool succeedOnOpen = true;

  @override
  void open(
    RazorpayCheckoutRequest request, {
    required RazorpayOnSuccess onSuccess,
    required RazorpayOnError onError,
    required RazorpayOnExternalWallet onExternalWallet,
  }) {
    opened.add(request);
    if (succeedOnOpen) {
      onSuccess('pay_1', request.orderId, 'sig_123');
    } else {
      onError(2, 'Payment cancelled');
    }
  }

  @override
  void clear() {}
}

FundingOrder _order(FundingStatus status, {String ref = 'TS_5'}) =>
    FundingOrder(
      publicReference: ref,
      type: FundingType.support49,
      amountMinor: 4900,
      currency: 'INR',
      status: status,
      termsVersion: '2026-09-01',
      checkoutMode: 'hosted',
      createdAt: '2026-09-01T09:30:00Z',
    );

FundingOrder _hostedOrder() => const FundingOrder(
  publicReference: 'TS_777',
  type: FundingType.support49,
  amountMinor: 4900,
  currency: 'INR',
  status: FundingStatus.created,
  termsVersion: '2026-09-01',
  checkoutMode: 'hosted',
  keyId: 'rzp_test_key',
  orderId: 'order_777',
);

Future<void> useTallSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(420, 1700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Widget _wrap(ProviderContainer container, GoRouter router) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    );

void main() {
  group('FundingScreen (isolation)', () {
    testWidgets('renders with no database and no network on first paint', (
      tester,
    ) async {
      await useTallSurface(tester);
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: FundingScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Support Funding'), findsOneWidget);
      expect(find.text('Future Funding'), findsOneWidget);
      expect(
        find.text('Draft documentation — not final legal advice.'),
        findsOneWidget,
      );
    });

    test('funding providers resolve without any database provider', () {
      final container = ProviderContainer(
        overrides: [
          fundingApiClientProvider.overrideWithValue(
            FundingApiClient(baseUrl: 'http://funding-test.invalid'),
          ),
        ],
      );
      addTearDown(container.dispose);

      final repo = container.read(fundingRepositoryProvider);
      expect(repo, isA<FundingRepository>());
    });
  });

  group('FundingHistoryScreen', () {
    late _FakeFundingRepository fake;

    setUp(() => fake = _FakeFundingRepository());

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [fundingRepositoryProvider.overrideWithValue(fake)],
          child: const MaterialApp(home: FundingHistoryScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows the empty state', (tester) async {
      await pump(tester);
      expect(find.text('No funding yet'), findsOneWidget);
    });

    testWidgets('lists orders with server amounts and status chips', (
      tester,
    ) async {
      fake.history = [
        _order(FundingStatus.verified),
        _order(FundingStatus.failed, ref: 'TS_6'),
      ];
      await pump(tester);

      expect(find.text('₹49.00'), findsNWidgets(2));
      expect(find.text('VERIFIED'), findsOneWidget);
      expect(find.text('FAILED'), findsOneWidget);
      expect(find.text('TS_5'), findsOneWidget);
      expect(find.text('TS_6'), findsOneWidget);
    });

    testWidgets('shows the offline message on a network failure', (
      tester,
    ) async {
      final failing = _NetworkFailingRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [fundingRepositoryProvider.overrideWithValue(failing)],
          child: const MaterialApp(home: FundingHistoryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'An internet connection is required to load funding '
          'history.',
        ),
        findsOneWidget,
      );
    });
  });

  group('FundingCheckoutScreen → FundingResultScreen', () {
    late _FakeFundingRepository fake;
    late ProviderContainer container;
    late GoRouter router;

    setUp(() {
      fake = _FakeFundingRepository();
      container = ProviderContainer(
        overrides: [
          fundingRepositoryProvider.overrideWithValue(fake),
          connectivityCheckerProvider.overrideWithValue(_FakeConnectedChecker()),
          fundingApiClientProvider.overrideWithValue(_FakeFundingApiClient()),
        ],
      );
      router = GoRouter(
        initialLocation: '/funding/checkout?type=SUPPORT_49',
        routes: [
          GoRoute(
            path: '/funding/checkout',
            builder: (context, state) => FundingCheckoutScreen(
              typeWire: state.uri.queryParameters['type'] ?? 'SUPPORT_49',
            ),
          ),
          GoRoute(
            path: '/funding/result',
            builder: (context, state) => FundingResultScreen(
              publicReference: state.uri.queryParameters['ref'] ?? '',
            ),
          ),
        ],
      );
    });

    tearDown(() => container.dispose());

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(_wrap(container, router));
      await tester.pumpAndSettle();
    }

    testWidgets('continue is gated on accepting the funding terms', (
      tester,
    ) async {
      await useTallSurface(tester);
      await pump(tester);

      final continueButton = find.widgetWithText(
        FilledButton,
        'Continue to payment',
      );
      expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);

      await tester.tap(find.text('I accept the Funding Terms'));
      await tester.pumpAndSettle();

      expect(tester.widget<FilledButton>(continueButton).onPressed, isNotNull);
    });

    testWidgets(
      'creates one order, simulates success, and lands on a receipt',
      (tester) async {
        await useTallSurface(tester);
        await pump(tester);

        // Review shows the display amount only.
        expect(find.text('₹49'), findsOneWidget);

        await tester.tap(find.text('I accept the Funding Terms'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Continue to payment'));
        await tester.pumpAndSettle();

        // Server amount is now authoritatively shown.
        expect(fake.createdTypes, ['SUPPORT_49']);
        expect(find.text('₹49.00'), findsOneWidget);
        expect(find.text('Sandbox checkout'), findsOneWidget);

        await tester.tap(find.text('Complete payment (simulated success)'));
        await tester.pumpAndSettle();

        expect(fake.simulated, ['TS_4242:success']);
        expect(find.text('Payment received'), findsOneWidget);
        expect(
          find.text('Thank you for supporting TripSplit.'),
          findsOneWidget,
        );
        expect(find.text('TS_4242'), findsOneWidget);
        expect(
          router.routerDelegate.currentConfiguration.uri.toString(),
          '/funding/result?ref=TS_4242',
        );
      },
    );

    testWidgets('a failed simulation lands on a payment-failed outcome', (
      tester,
    ) async {
      await useTallSurface(tester);
      await pump(tester);

      await tester.tap(find.text('I accept the Funding Terms'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue to payment'));
      await tester.pumpAndSettle();
      fake.statusResult = _order(FundingStatus.failed, ref: 'TS_4242');
      await tester.tap(find.text('Fail payment (simulated)'));
      await tester.pumpAndSettle();

      expect(find.text('Payment failed'), findsOneWidget);
      expect(find.textContaining('No money was charged.'), findsOneWidget);
    });

    testWidgets('offline order creation shows the internet message', (
      tester,
    ) async {
      await useTallSurface(tester);
      fake.createError = const FundingException(
        FundingFailureKind.offline,
        'An internet connection is required to process funding.',
      );
      await pump(tester);

      await tester.tap(find.text('I accept the Funding Terms'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue to payment'));
      await tester.pumpAndSettle();

      expect(
        find.text('An internet connection is required to process funding.'),
        findsOneWidget,
      );
      expect(find.text('Sandbox checkout'), findsNothing);
    });

    testWidgets(
      'hosted order auto-launches checkout, verifies, and lands on a receipt',
      (tester) async {
        await useTallSurface(tester);
        final launcher = _RecordingCheckoutLauncher();
        container = ProviderContainer(
          overrides: [
            fundingRepositoryProvider.overrideWithValue(fake),
            razorpayCheckoutLauncherProvider.overrideWithValue(launcher),
            connectivityCheckerProvider.overrideWithValue(
              _FakeConnectedChecker(),
            ),
            fundingApiClientProvider.overrideWithValue(_FakeFundingApiClient()),
          ],
        );
        fake.createResult = _hostedOrder();

        await pump(tester);
        await tester.tap(find.text('I accept the Funding Terms'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Continue to payment'));
        await tester.pumpAndSettle();

        expect(fake.createdTypes, ['SUPPORT_49']);
        expect(launcher.opened.single.keyId, 'rzp_test_key');
        expect(launcher.opened.single.orderId, 'order_777');
        expect(launcher.opened.single.amountMinor, 4900);
        expect(launcher.opened.single.currency, 'INR');
        expect(fake.verifyCalls, hasLength(1));
        expect(fake.verifyCalls.single.ref, 'TS_777');
        expect(fake.verifyCalls.single.orderId, 'order_777');
        expect(fake.verifyCalls.single.paymentId, 'pay_1');
        expect(fake.verifyCalls.single.signature, 'sig_123');
        expect(find.text('Payment received'), findsOneWidget);
        expect(
          router.routerDelegate.currentConfiguration.uri.toString(),
          '/funding/result?ref=TS_777',
        );
      },
    );

    testWidgets('a cancelled hosted checkout stays put and can retry', (
      tester,
    ) async {
      await useTallSurface(tester);
      final launcher = _RecordingCheckoutLauncher()..succeedOnOpen = false;
      container = ProviderContainer(
        overrides: [
          fundingRepositoryProvider.overrideWithValue(fake),
          razorpayCheckoutLauncherProvider.overrideWithValue(launcher),
          connectivityCheckerProvider.overrideWithValue(
            _FakeConnectedChecker(),
          ),
          fundingApiClientProvider.overrideWithValue(_FakeFundingApiClient()),
        ],
      );
      fake.createResult = _hostedOrder();

      await pump(tester);
      await tester.tap(find.text('I accept the Funding Terms'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue to payment'));
      await tester.pumpAndSettle();

      expect(fake.verifyCalls, isEmpty);
      expect(find.text('Payment cancelled'), findsOneWidget);
      expect(find.text('Open secure checkout'), findsOneWidget);
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/funding/checkout?type=SUPPORT_49',
      );

      await tester.tap(find.text('Open secure checkout'));
      await tester.pumpAndSettle();
      expect(launcher.opened, hasLength(2));
    });

    testWidgets('a lost verify response still reaches the receipt screen', (
      tester,
    ) async {
      await useTallSurface(tester);
      final launcher = _RecordingCheckoutLauncher();
      container = ProviderContainer(
        overrides: [
          fundingRepositoryProvider.overrideWithValue(fake),
          razorpayCheckoutLauncherProvider.overrideWithValue(launcher),
          connectivityCheckerProvider.overrideWithValue(
            _FakeConnectedChecker(),
          ),
          fundingApiClientProvider.overrideWithValue(_FakeFundingApiClient()),
        ],
      );
      fake.createResult = _hostedOrder();
      fake.verifyError = const FundingException(
        FundingFailureKind.offline,
        'An internet connection is required to process funding.',
      );
      fake.statusResult = _order(FundingStatus.paymentPending, ref: 'TS_777');

      await pump(tester);
      await tester.tap(find.text('I accept the Funding Terms'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue to payment'));
      // The receipt page keeps a status spinner animating while a payment is
      // pending, so pumpAndSettle would never finish — pump frames instead.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // The lost response must never be marked failed: the receipt shows the
      // authoritative status (pending here) instead.
      expect(find.text('Payment pending'), findsOneWidget);
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/funding/result?ref=TS_777',
      );
    });
  });
}

class _NetworkFailingRepository extends FundingRepository {
  _NetworkFailingRepository()
    : super(FundingApiClient(baseUrl: 'http://funding-test.invalid'));

  @override
  Future<List<FundingOrder>> fetchHistory() async {
    throw const FundingException(
      FundingFailureKind.offline,
      'An internet connection is required to load funding history.',
    );
  }
}
