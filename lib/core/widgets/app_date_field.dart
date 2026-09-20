import 'package:flutter/material.dart';

import '../../app/theme/app_radius.dart';
import '../../app/theme/app_text_styles.dart';
import '../utils/date_format.dart';

/// Tappable date field that opens a Material date picker.
///
/// Encapsulates the calendar entry icon, formatted display and the optional
/// clear affordance so every date input behaves and looks identical.
class AppDateField extends StatelessWidget {
  const AppDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hintText,
    this.firstDate,
    this.lastDate,
    this.clearable = false,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final String? hintText;

  /// Earliest selectable date. Defaults to 2020.
  final DateTime? firstDate;

  /// Latest selectable date. Defaults to one year from today.
  final DateTime? lastDate;

  /// When `true` a clear (×) suffix is shown once a date is set.
  final bool clearable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayText = value != null
        ? DateFormats.date(value!)
        : (hintText ?? 'Not set');
    final shown = value != null;

    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          firstDate: firstDate ?? DateTime(2020),
          lastDate: lastDate ?? DateTime(now.year + 1),
        );
        if (picked != null) {
          onChanged(picked);
        }
      },
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: clearable && shown
              ? IconButton(
                  tooltip: 'Clear $label',
                  onPressed: () => onChanged(null),
                  icon: const Icon(Icons.close, size: 20),
                )
              : const Icon(Icons.calendar_today, size: 20),
          suffixIconColor: theme.colorScheme.onSurfaceVariant,
        ),
        child: Text(
          displayText,
          style: shown ? theme.textTheme.bodyLarge : theme.textTheme.bodyMuted,
        ),
      ),
    );
  }
}
