import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/app/theme/app_theme.dart';
import 'package:tripsplit/core/widgets/app_confirmation_dialog.dart';
import 'package:tripsplit/core/widgets/app_section_header.dart';
import 'package:tripsplit/core/widgets/status_chip.dart';

/// Widget-level coverage for the shared UI components introduced in the
/// design system overhaul. These tests guard labels, presentation, and the
/// confirmation-dialog contract used across the app.
void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: child),
  );

  group('StatusChip', () {
    testWidgets('renders uppercase label with tone text', (tester) async {
      await tester.pumpWidget(wrap(const StatusChip('Receives')));

      expect(find.text('RECEIVES'), findsOneWidget);
      expect(find.byType(StatusChip), findsOneWidget);
    });

    testWidgets('exposes semantic label for screen readers', (tester) async {
      await tester.pumpWidget(wrap(const StatusChip('Owes')));

      final semantics = tester.getSemantics(find.byType(StatusChip));
      expect(semantics.label, contains('Owes'));
    });
  });

  group('SectionHeader', () {
    testWidgets('shows title', (tester) async {
      await tester.pumpWidget(wrap(const SectionHeader('Group summary')));

      expect(find.text('Group summary'), findsOneWidget);
    });

    testWidgets('shows trailing action when provided', (tester) async {
      await tester.pumpWidget(
        wrap(
          SectionHeader(
            'History',
            trailing: TextButton(
              onPressed: () {},
              child: const Text('See all'),
            ),
          ),
        ),
      );

      expect(find.text('History'), findsOneWidget);
      expect(find.text('See all'), findsOneWidget);
    });
  });

  group('AppConfirmationDialog', () {
    testWidgets('confirm resolves true, cancel resolves false', (tester) async {
      bool? result;
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showAppConfirmation(
                  context,
                  title: 'Remove member?',
                  message: 'Their history will be deleted.',
                  confirmLabel: 'Remove',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Remove member?'), findsOneWidget);
      expect(find.text('Their history will be deleted.'), findsOneWidget);

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('cancel resolves false', (tester) async {
      bool? result;
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showAppConfirmation(
                  context,
                  title: 'Remove member?',
                  message: 'Their history will be deleted.',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });
  });
}
