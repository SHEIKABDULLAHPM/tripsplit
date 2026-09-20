import 'package:flutter/material.dart';

/// Confirmation dialog with an explicit cancel affordance.
///
/// Destructive confirmations use the error palette so destructive intents are
/// immediately obvious; non-destructive ones use the primary color.
///
/// Show with [showAppConfirmation] which resolves to `true` when confirmed.
class AppConfirmationDialog extends StatelessWidget {
  const AppConfirmationDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmLabel = 'Delete',
    this.cancelLabel = 'Cancel',
    this.destructive = true,
    this.confirmIcon = Icons.check,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;
  final IconData confirmIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      icon: Icon(
        destructive ? Icons.error_outline : Icons.info_outline,
        color: destructive
            ? theme.colorScheme.error
            : theme.colorScheme.primary,
      ),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: destructive
                ? theme.colorScheme.error
                : theme.colorScheme.primary,
            foregroundColor: destructive
                ? theme.colorScheme.onError
                : theme.colorScheme.onPrimary,
          ),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}

/// Shows [AppConfirmationDialog] and resolves with the user's decision.
Future<bool> showAppConfirmation(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  String cancelLabel = 'Cancel',
  bool destructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AppConfirmationDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      destructive: destructive,
    ),
  );
  return result ?? false;
}
