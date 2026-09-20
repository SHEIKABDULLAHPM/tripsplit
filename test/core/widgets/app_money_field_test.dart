import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/app/theme/app_theme.dart';
import 'package:tripsplit/core/widgets/app_money_field.dart';

/// Guards the shared money-input validation contract used by every monetary
/// field in the app (amount, contribution, budget, external).
void main() {
  late TextEditingController controller;
  late FormFieldValidator<String> validator;

  Future<void> pumpField(WidgetTester tester, AppMoneyField field) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Form(child: Builder(builder: (context) => field)),
        ),
      ),
    );
    validator =
        tester.widget<TextFormField>(find.byType(TextFormField)).validator ??
        (_) => null;
  }

  setUp(() {
    controller = TextEditingController();
  });

  tearDown(() {
    controller.dispose();
  });

  testWidgets('required field rejects empty input', (tester) async {
    await pumpField(
      tester,
      AppMoneyField(
        controller: controller,
        label: 'Amount',
        constraint: AppMoneyConstraint.requiredPositive,
      ),
    );
    expect(validator(''), 'Please enter an amount');
  });

  testWidgets('required field rejects zero, accepts positive', (tester) async {
    await pumpField(
      tester,
      AppMoneyField(
        controller: controller,
        label: 'Amount',
        constraint: AppMoneyConstraint.requiredPositive,
      ),
    );
    expect(validator('0'), 'Amount must be more than zero.');
    expect(validator('0.00'), 'Amount must be more than zero.');
    expect(validator('100'), isNull);
    expect(validator('100.00'), isNull);
  });

  testWidgets('negative input uses tailored message when supplied', (
    tester,
  ) async {
    await pumpField(
      tester,
      AppMoneyField(
        controller: controller,
        label: 'External',
        constraint: AppMoneyConstraint.optionalNonNegative,
        negativeMessage:
            'Must be smaller than the amount so some of the expense is shared.',
      ),
    );
    expect(validator(''), isNull);
    expect(validator('0'), isNull);
    expect(validator('100'), isNull);
    expect(
      validator('-1'),
      'Must be smaller than the amount so some of the expense is shared.',
    );
  });

  testWidgets('negative input falls back to standard message otherwise', (
    tester,
  ) async {
    await pumpField(
      tester,
      AppMoneyField(
        controller: controller,
        label: 'Contribution',
        constraint: AppMoneyConstraint.requiredPositive,
      ),
    );
    expect(validator('-1'), 'Enter a valid amount.');
  });

  testWidgets('malformed input maps to standard message', (tester) async {
    await pumpField(
      tester,
      AppMoneyField(
        controller: controller,
        label: 'Contribution',
        constraint: AppMoneyConstraint.requiredPositive,
      ),
    );
    expect(validator('abc'), 'Enter a valid amount.');
    expect(validator('1.234'), 'Enter a valid amount.');
    expect(validator('100.'), isNull);
  });

  testWidgets('max minor limit rejects overshoot with given message', (
    tester,
  ) async {
    await pumpField(
      tester,
      AppMoneyField(
        controller: controller,
        label: 'External',
        constraint: AppMoneyConstraint.optionalNonNegative,
        maxMinor: 10000,
        maxStrict: true,
        maxExceededMessage:
            'Must be smaller than the amount so some of the expense is shared.',
      ),
    );
    expect(
      validator('250'),
      'Must be smaller than the amount so some of the expense is shared.',
    );
    expect(
      validator('200'),
      'Must be smaller than the amount so some of the expense is shared.',
    );
    expect(
      validator('100'),
      'Must be smaller than the amount so some of the expense is shared.',
    );
    expect(validator('99'), isNull);
  });
}
