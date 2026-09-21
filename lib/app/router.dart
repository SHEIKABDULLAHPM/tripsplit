import 'package:go_router/go_router.dart';

import '../features/balances/presentation/balances_screen.dart';
import '../features/expenses/presentation/expense_details_screen.dart';
import '../features/expenses/presentation/expense_form_screen.dart';
import '../features/expenses/presentation/expense_management_screen.dart';
import '../features/funding/presentation/funding_checkout_screen.dart';
import '../features/funding/presentation/funding_document_screen.dart';
import '../features/funding/presentation/funding_result_screen.dart';
import '../features/funding/presentation/funding_screen.dart';
import '../features/journey/presentation/journey_screen.dart';
import '../features/members/presentation/add_contribution_screen.dart';
import '../features/members/presentation/add_member_screen.dart';
import '../features/members/presentation/member_detail_screen.dart';
import '../features/members/presentation/people_screen.dart';
import '../features/notes/presentation/notes_screen.dart';
import '../features/settlements/presentation/record_settlement_screen.dart';
import '../features/settlements/presentation/settlement_detail_screen.dart';
import '../features/settlements/presentation/settlements_screen.dart';
import '../features/teams/presentation/team_settlement_screen.dart';
import '../features/teams/presentation/teams_screen.dart';
import '../features/trips/presentation/create_trip_screen.dart';
import '../features/trips/presentation/trip_dashboard_screen.dart';
import 'screens/more_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/welcome_screen.dart';
import 'widgets/home_screen.dart';

/// Central route-path constants.
abstract final class AppRoutes {
  AppRoutes._();

  static const String splash = '/splash';
  static const String welcome = '/welcome';
  static const String onboarding = '/onboarding';

  static const String home = '/';
  static const String createTrip = '/trips/new';

  // App-level funding routes (never trip-scoped; funding is isolated).
  static const String funding = '/funding';
  static String fundingCheckout(String typeWire) =>
      '/funding/checkout?type=$typeWire';
  static String fundingResult(String reference) =>
      '/funding/result?ref=${Uri.encodeComponent(reference)}';
  static String fundingDocument(String name) => '/funding/document?name=$name';

  static String trip(int tripId) => '/trip/$tripId';
  static String more(int tripId) => '/trip/$tripId/more';
  static String notes(int tripId) => '/trip/$tripId/notes';

  static String people(int tripId) => '/trip/$tripId/members';
  static String memberDetail(int tripId, int memberId) =>
      '/trip/$tripId/members/$memberId';
  static String addMember(int tripId) => '/trip/$tripId/members/new';
  static String addContribution(int tripId) =>
      '/trip/$tripId/contributions/new';
  static String journey(int tripId) => '/trip/$tripId/journey';
  static String teams(int tripId) => '/trip/$tripId/teams';
  static String expenses(int tripId) => '/trip/$tripId/expenses';
  static String addExpense(
    int tripId, {
    int? segmentId,
    int? teamId,
    int? payerMemberId,
  }) {
    final params = <String, String>{};
    if (segmentId != null) params['segmentId'] = segmentId.toString();
    if (teamId != null) params['teamId'] = teamId.toString();
    if (payerMemberId != null) params['payerId'] = payerMemberId.toString();
    if (params.isEmpty) return '/trip/$tripId/expenses/new';
    final qs = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    return '/trip/$tripId/expenses/new?$qs';
  }

  static String expense(int tripId, int expenseId) =>
      '/trip/$tripId/expenses/$expenseId';
  static String editExpense(int tripId, int expenseId) =>
      '/trip/$tripId/expenses/$expenseId/edit';
  static String balances(int tripId) => '/trip/$tripId/balances';
  static String settlements(int tripId) => '/trip/$tripId/settlements';
  static String settlementDetail(int tripId, int settlementId) =>
      '/trip/$tripId/settlements/$settlementId';
  static String recordSettlement(int tripId) => '/trip/$tripId/settlements/new';
  static String teamSettlement(
    int tripId,
    int teamId, {
    String name = 'Team',
  }) =>
      '/trip/$tripId/teams/$teamId/settlement?name=${Uri.encodeComponent(name)}';
}

/// Builds the application's navigation graph.
abstract final class AppRouter {
  AppRouter._();

  static GoRouter create() => GoRouter(
    initialLocation: AppRoutes.splash,
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.welcome,
        name: 'welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        name: 'onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.createTrip,
        name: 'create-trip',
        builder: (context, state) => const CreateTripScreen(),
      ),
      GoRoute(
        path: AppRoutes.funding,
        name: 'funding',
        builder: (context, state) => const FundingScreen(),
      ),
      GoRoute(
        path: '/funding/checkout',
        name: 'funding-checkout',
        builder: (context, state) => FundingCheckoutScreen(
          typeWire: state.uri.queryParameters['type'] ?? 'SUPPORT_49',
        ),
      ),
      GoRoute(
        path: '/funding/result',
        name: 'funding-result',
        builder: (context, state) => FundingResultScreen(
          publicReference: state.uri.queryParameters['ref'] ?? '',
        ),
      ),
      GoRoute(
        path: '/funding/document',
        name: 'funding-document',
        builder: (context, state) => FundingDocumentScreen(
          documentName: state.uri.queryParameters['name'] ?? 'overview',
        ),
      ),
      GoRoute(
        path: '/trip/:tripId',
        name: 'trip',
        builder: (context, state) => TripDashboardScreen(
          tripId: _parseId(state.pathParameters['tripId']),
        ),
        routes: [
          GoRoute(
            path: 'more',
            name: 'more',
            builder: (context, state) =>
                MoreScreen(tripId: _parseId(state.pathParameters['tripId'])),
          ),
          GoRoute(
            path: 'notes',
            name: 'notes',
            builder: (context, state) =>
                NotesScreen(tripId: _parseId(state.pathParameters['tripId'])),
          ),
          GoRoute(
            path: 'members',
            name: 'people',
            builder: (context, state) =>
                PeopleScreen(tripId: _parseId(state.pathParameters['tripId'])),
            routes: [
              // Static segment must precede ':memberId' so GoRouter resolves
              // '/members/new' to the add screen instead of a missing member.
              GoRoute(
                path: 'new',
                name: 'add-member',
                builder: (context, state) => AddMemberScreen(
                  tripId: _parseId(state.pathParameters['tripId']),
                ),
              ),
              GoRoute(
                path: ':memberId',
                name: 'member-detail',
                builder: (context, state) => MemberDetailScreen(
                  tripId: _parseId(state.pathParameters['tripId']),
                  memberId: _parseId(state.pathParameters['memberId']),
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'contributions/new',
            name: 'add-contribution',
            builder: (context, state) => AddContributionScreen(
              tripId: _parseId(state.pathParameters['tripId']),
            ),
          ),
          GoRoute(
            path: 'journey',
            name: 'journey',
            builder: (context, state) =>
                JourneyScreen(tripId: _parseId(state.pathParameters['tripId'])),
          ),
          GoRoute(
            path: 'teams',
            name: 'teams',
            builder: (context, state) =>
                TeamsScreen(tripId: _parseId(state.pathParameters['tripId'])),
            routes: [
              GoRoute(
                path: ':teamId/settlement',
                name: 'team-settlement',
                builder: (context, state) => TeamSettlementScreen(
                  tripId: _parseId(state.pathParameters['tripId']),
                  teamId: _parseId(state.pathParameters['teamId']),
                  teamName: state.uri.queryParameters['name'] ?? 'Team',
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'expenses',
            name: 'expenses',
            builder: (context, state) => ExpenseManagementScreen(
              tripId: _parseId(state.pathParameters['tripId']),
            ),
          ),
          GoRoute(
            path: 'expenses/new',
            name: 'add-expense',
            builder: (context, state) {
              final tripId = _parseId(state.pathParameters['tripId']);
              final segmentId = int.tryParse(
                state.uri.queryParameters['segmentId'] ?? '',
              );
              final teamId = int.tryParse(
                state.uri.queryParameters['teamId'] ?? '',
              );
              final payerId = int.tryParse(
                state.uri.queryParameters['payerId'] ?? '',
              );
              return ExpenseFormScreen.create(
                tripId: tripId,
                initialSegmentId: segmentId,
                initialTeamId: teamId,
                initialPayerId: payerId,
              );
            },
          ),
          GoRoute(
            path: 'expenses/:expenseId',
            name: 'expense-details',
            builder: (context, state) => ExpenseDetailsScreen(
              tripId: _parseId(state.pathParameters['tripId']),
              expenseId: _parseId(state.pathParameters['expenseId']),
            ),
            routes: [
              GoRoute(
                path: 'edit',
                name: 'edit-expense',
                builder: (context, state) => ExpenseFormScreen.edit(
                  tripId: _parseId(state.pathParameters['tripId']),
                  expenseId: _parseId(state.pathParameters['expenseId']),
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'balances',
            name: 'balances',
            builder: (context, state) => BalancesScreen(
              tripId: _parseId(state.pathParameters['tripId']),
            ),
          ),
          GoRoute(
            path: 'settlements',
            name: 'settlements',
            builder: (context, state) => SettlementsScreen(
              tripId: _parseId(state.pathParameters['tripId']),
            ),
            routes: [
              // Static segment must precede ':settlementId' so GoRouter
              // resolves '/settlements/new' to the record screen instead of a
              // missing settlement.
              GoRoute(
                path: 'new',
                name: 'record-settlement',
                builder: (context, state) => RecordSettlementScreen(
                  tripId: _parseId(state.pathParameters['tripId']),
                ),
              ),
              GoRoute(
                path: ':settlementId',
                name: 'settlement-detail',
                builder: (context, state) => SettlementDetailScreen(
                  tripId: _parseId(state.pathParameters['tripId']),
                  settlementId: _parseId(state.pathParameters['settlementId']),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );

  static int _parseId(String? value) => int.tryParse(value ?? '') ?? 0;
}
