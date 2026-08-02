import 'package:flutter/material.dart';

import '../services/metrics.dart';
import '../theme/tokens.dart';

/// A number that eases to its new value instead of snapping.
///
/// The tween is the whole point of the hero figure: seeing 8 400 climb to
/// 8 432 tells you the counter is live in a way a static number cannot.
/// Tabular figures in [AppText] keep the digits from jittering as they roll.
class AnimatedCounter extends StatelessWidget {
  const AnimatedCounter({
    super.key,
    required this.value,
    required this.style,
    this.formatter = formatSteps,
    this.duration = AppDuration.counter,
  });

  final int value;
  final TextStyle style;
  final String Function(int) formatter;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    // Users who asked the system to reduce motion get the final number.
    final animate = !MediaQuery.disableAnimationsOf(context);

    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.toDouble()),
      duration: animate ? duration : Duration.zero,
      curve: AppCurves.outExpo,
      builder: (context, animated, _) =>
          Text(formatter(animated.round()), style: style),
    );
  }
}
