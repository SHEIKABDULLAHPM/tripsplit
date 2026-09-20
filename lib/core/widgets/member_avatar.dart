import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Deterministic initial-letter avatar for a trip member.
///
/// The background is picked from a fixed palette keyed by the member name so
/// the same person always gets the same color across screens.
class MemberAvatar extends StatelessWidget {
  const MemberAvatar(this.name, {super.key, this.radius = 20});

  final String name;
  final double radius;

  static const List<Color> _palette = [
    AppColors.primaryContainer,
    AppColors.secondaryContainer,
    AppColors.tertiaryContainer,
    AppColors.surfaceContainerHighest,
    AppColors.surface2,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = (name.isEmpty ? '?' : name[0]).toUpperCase();
    final index = name.hashCode.abs() % _palette.length;
    final background = _palette[index];

    return Semantics(
      excludeSemantics: true,
      label: 'Avatar for $name',
      child: CircleAvatar(
        radius: radius,
        backgroundColor: background,
        child: Text(
          initial,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
