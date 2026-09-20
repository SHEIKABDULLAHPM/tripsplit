import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_icon_sizes.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_text_styles.dart';
import '../errors/app_exception.dart';
import 'loading_state.dart';

/// Renders an [AsyncValue] with loading, error and data states.
///
/// [isEmpty] reports whether [data] should be treated as "empty", in which
/// case [empty] is shown instead.
class AsyncValueView<T> extends ConsumerWidget {
  const AsyncValueView({
    super.key,
    required this.value,
    required this.builder,
    this.isEmpty,
    this.empty,
    this.loading,
    this.errorMessageBuilder,
    this.onRetry,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;

  /// Optional predicate deciding whether [data] is "empty".
  final bool Function(T data)? isEmpty;
  final Widget? empty;
  final Widget? loading;

  /// Maps an error to a human-friendly summary line.
  final String Function(Object error)? errorMessageBuilder;

  /// Optional retry action shown on errors (e.g. invalidating the provider).
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) => value.when(
    data: (data) => data == null || (isEmpty?.call(data) ?? false)
        ? empty ?? const SizedBox.shrink()
        : builder(data),
    loading: () => loading ?? const LoadingState(),
    error: (error, stackTrace) => _errorView(context, error),
  );

  Widget _errorView(BuildContext context, Object error) {
    final theme = Theme.of(context);
    final message =
        errorMessageBuilder?.call(error) ??
        (error is AppException ? error.message : 'Could not load this data.');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: AppIconSizes.xl * 1.5,
              height: AppIconSizes.xl * 1.5,
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline,
                size: AppIconSizes.xl,
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Could not load',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMuted,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (onRetry != null)
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
          ],
        ),
      ),
    );
  }
}
