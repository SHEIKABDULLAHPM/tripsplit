import 'package:flutter/material.dart';

import '../../app/theme/app_text_styles.dart';
import '../calculations/money.dart';
import '../errors/app_exception.dart';

/// Money constraint applied to an [AppMoneyField].
enum AppMoneyConstraint {
  /// Any non-negative amount is allowed (may be empty).
  optional,

  /// A strictly positive amount is required.
  requiredPositive,

  /// Amount must be non-negative when provided; the field is optional.
  optionalNonNegative,
}

/// Standardized money input used across the app.
///
/// Encapsulates the number keyboard, label, hint and shared validation rules
/// so every monetary field behaves and looks identical. The build output is a
/// single [TextFormField], keeping existing structural finders compatible.
class AppMoneyField extends StatelessWidget {
  const AppMoneyField({
    super.key,
    required this.controller,
    required this.label,
    required this.constraint,
    this.hintText,
    this.helperText,
    this.errorLabel = 'Amount',
    this.requiredMessage = 'Please enter an amount',
    this.negativeMessage,
    this.maxMinor,
    this.maxStrict = false,
    this.maxExceededMessage,
    this.enabled = true,
    this.autofocus = false,
    this.textInputAction,
    this.onChanged,
    this.contentPadding,
  });

  final TextEditingController controller;
  final String label;
  final AppMoneyConstraint constraint;
  final String? hintText;
  final String? helperText;

  /// Optional override for the field's inner padding. Defaults to the app
  /// input theme so compact rows can align with other dense fields.
  final EdgeInsetsGeometry? contentPadding;

  /// Field name used in error messages (e.g. "Amount", "Contribution").
  final String errorLabel;

  /// Message shown when a required field is left empty.
  final String requiredMessage;

  /// Custom message shown for negative values.
  final String? negativeMessage;

  /// When set, values greater than (or equal to, if [maxStrict]) are rejected.
  final int? maxMinor;

  /// `true` rejects `>= `maxMinor` (e.g. external must stay below amount).
  final bool maxStrict;

  /// Custom message shown when [maxMinor] is exceeded.
  final String? maxExceededMessage;

  final bool enabled;
  final bool autofocus;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextFormField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      textInputAction: textInputAction,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        helperText: helperText,
        contentPadding: contentPadding,
        helperStyle: theme.textTheme.captionMuted,
      ),
      onChanged: onChanged,
      validator: _validate,
    );
  }

  String? _validate(String? value) {
    final text = value?.trim() ?? '';
    final provided = text.isNotEmpty;

    if (!provided) {
      if (constraint == AppMoneyConstraint.requiredPositive) {
        return requiredMessage;
      }
      return null;
    }

    if (text.contains('-')) {
      // Only emit a tailored message when one is supplied; otherwise fall
      // through to the parser, which reports the value as invalid.
      if (negativeMessage != null) {
        return negativeMessage;
      }
    }

    int minor;
    try {
      minor = MoneyCalculator.parseToMinor(text, label: errorLabel);
    } on AppException {
      return 'Enter a valid amount.';
    }

    if (constraint == AppMoneyConstraint.requiredPositive && minor <= 0) {
      return 'Amount must be more than zero.';
    }

    if (maxMinor != null) {
      final over = maxStrict ? minor >= maxMinor! : minor > maxMinor!;
      if (over) {
        return maxExceededMessage ??
            (maxStrict
                ? 'Must be smaller than the maximum amount.'
                : 'Cannot exceed the maximum amount.');
      }
    }

    return null;
  }
}
