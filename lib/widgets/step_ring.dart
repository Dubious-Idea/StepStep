import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The hero progress ring.
///
/// Deliberately hand-painted rather than a `CircularProgressIndicator`: the
/// sweep gradient, the glow and the head dot are what carry the whole visual
/// direction, and none of them exist in the stock widget.
///
/// The Kotlin twin in `RingRenderer.kt` draws the same ring for the widget and
/// the notification — keep the two in step.
class StepRing extends StatelessWidget {
  const StepRing({
    super.key,
    required this.progress,
    required this.goalReached,
    this.strokeWidth = 20,
    this.child,
  });

  final double progress;
  final bool goalReached;
  final double strokeWidth;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, constraints.maxHeight);
        return SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _RingPainter(
              progress: progress.clamp(0.0, 1.0),
              goalReached: goalReached,
              strokeWidth: strokeWidth,
            ),
            child: Center(child: child),
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.goalReached,
    required this.strokeWidth,
  });

  final double progress;
  final bool goalReached;
  final double strokeWidth;

  /// Progress starts at 12 o'clock and runs clockwise.
  static const double _startAngle = -math.pi / 2;

  /// Keeps a zero-step ring reading as "ready" rather than broken.
  static const double _minSweep = 0.045;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2 - strokeWidth * 0.6;
    final rect = Rect.fromCircle(center: center, radius: radius);

    _paintTrack(canvas, center, radius);

    final sweep = _minSweep + progress * (2 * math.pi - _minSweep);

    // Glow underneath, crisp stroke on top — the other order reads muddy.
    // The glow needs its own alpha-reduced shader: a Paint's `color` is
    // ignored once a shader is set, so opacity has to live in the gradient.
    canvas.drawArc(
      rect,
      _startAngle,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * 1.05
        ..strokeCap = StrokeCap.round
        ..shader = _sweepShader(rect, opacity: 0.5)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, strokeWidth * 0.75),
    );

    canvas.drawArc(
      rect,
      _startAngle,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..shader = _sweepShader(rect),
    );

    _paintHead(canvas, center, radius, sweep);
  }

  Shader _sweepShader(Rect rect, {double opacity = 1}) {
    final base = goalReached
        ? AppColors.goalReachedGradient
        : AppColors.ringGradient;
    return SweepGradient(
      startAngle: 0,
      endAngle: 2 * math.pi,
      colors: opacity == 1
          ? base
          : base.map((c) => c.withValues(alpha: opacity)).toList(),
      stops: const [0, 0.35, 0.72, 1],
      transform: const GradientRotation(_startAngle),
    ).createShader(rect);
  }

  void _paintTrack(Canvas canvas, Offset center, double radius) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = AppColors.stroke,
    );
  }

  void _paintHead(Canvas canvas, Offset center, double radius, double sweep) {
    final angle = _startAngle + sweep;
    final head = Offset(
      center.dx + radius * math.cos(angle),
      center.dy + radius * math.sin(angle),
    );
    final tint = goalReached
        ? AppColors.gold
        : _gradientColorAt(sweep / (2 * math.pi));

    canvas.drawCircle(
      head,
      strokeWidth * 0.45,
      Paint()
        ..color = tint.withValues(alpha: 0.6)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, strokeWidth * 0.6),
    );
    canvas.drawCircle(head, strokeWidth * 0.2, Paint()..color = Colors.white);
  }

  /// Approximates the sweep gradient at [t] so the head halo matches the arc.
  Color _gradientColorAt(double t) {
    final clamped = t.clamp(0.0, 1.0);
    if (clamped < 0.35) {
      return Color.lerp(
        AppColors.accentStart,
        AppColors.accentMid,
        clamped / 0.35,
      )!;
    }
    if (clamped < 0.72) {
      return Color.lerp(
        AppColors.accentMid,
        AppColors.accentEnd,
        (clamped - 0.35) / 0.37,
      )!;
    }
    return Color.lerp(
      AppColors.accentEnd,
      AppColors.accentStart,
      (clamped - 0.72) / 0.28,
    )!;
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.goalReached != goalReached ||
      oldDelegate.strokeWidth != strokeWidth;
}
