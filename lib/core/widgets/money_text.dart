import 'package:flutter/material.dart';

import '../calculations/money.dart';

/// Renders a minor-unit amount using [MoneyCalculator.format].
class MoneyText extends StatelessWidget {
  const MoneyText(this.minor, {super.key, this.style});

  final int minor;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Text(
    MoneyCalculator.format(minor),
    style: style,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
}
