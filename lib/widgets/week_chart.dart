import 'package:flutter/material.dart';

import '../models/day_stats.dart';
import '../services/metrics.dart';
import '../theme/tokens.dart';

/// Seven-day bar chart, hand-painted so it belongs to the same design system
/// as the ring rather than importing a charting library's default look.
///
/// Today is the only bar that gets the gradient — every other day is a quiet
/// graphite column, which is what makes "where am I now" readable at a glance.
class WeekChart extends StatelessWidget {
  const WeekChart({
    super.key,
    required this.days,
    required this.goal,
    this.height = 96,
  });

  final List<DayEntry> days;
  final int goal;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();

    final ceiling = chartCeiling(days.map((d) => d.steps).followedBy([goal]));
    final animate = !MediaQuery.disableAnimationsOf(context);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: animate ? AppDuration.ring : Duration.zero,
      curve: AppCurves.outExpo,
      builder: (context, t, _) => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < days.length; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  left: i == 0 ? 0 : AppSpacing.xs,
                  right: i == days.length - 1 ? 0 : AppSpacing.xs,
                ),
                child: _Bar(
                  entry: days[i],
                  ceiling: ceiling,
                  goal: goal,
                  isToday: i == days.length - 1,
                  height: height,
                  progress: t,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.entry,
    required this.ceiling,
    required this.goal,
    required this.isToday,
    required this.height,
    required this.progress,
  });

  final DayEntry entry;
  final int ceiling;
  final int goal;
  final bool isToday;
  final double height;
  final double progress;

  /// A stub so an empty day still reads as a day, not as missing data.
  static const double _minFraction = 0.03;

  @override
  Widget build(BuildContext context) {
    final fraction = (entry.steps / ceiling).clamp(_minFraction, 1.0);
    final reachedGoal = entry.steps >= goal;

    return Semantics(
      label: '${entry.shortName}: ${formatSteps(entry.steps)} шагов',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: height,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: fraction * progress,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    gradient: isToday
                        ? const LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              AppColors.accentEnd,
                              AppColors.accentMid,
                              AppColors.accentStart,
                            ],
                          )
                        : null,
                    color: isToday
                        ? null
                        : reachedGoal
                        ? AppColors.gold.withValues(alpha: 0.35)
                        : AppColors.surfaceRaised,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            entry.shortName,
            style: AppText.label.copyWith(
              fontSize: 10,
              letterSpacing: 0.4,
              color: isToday ? AppColors.textPrimary : AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
