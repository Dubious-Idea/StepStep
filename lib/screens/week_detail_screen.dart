import 'package:flutter/material.dart';

import '../models/day_stats.dart';
import '../services/metrics.dart';
import '../theme/tokens.dart';
import '../widgets/stat_card.dart';

/// Day-by-day breakdown behind the week card's average figure — the same
/// [DayEntry] list the chart already has, just read as a table instead of
/// bars, newest day first.
class WeekDetailScreen extends StatelessWidget {
  const WeekDetailScreen({super.key, required this.days, required this.goal});

  final List<DayEntry> days;
  final int goal;

  @override
  Widget build(BuildContext context) {
    final total = days.fold<int>(0, (sum, d) => sum + d.steps);
    final average = days.isEmpty ? 0 : total ~/ days.length;
    final newestFirst = days.reversed.toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Неделя')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            AppSpacing.lg,
            AppSpacing.screenPadding,
            AppSpacing.xl,
          ),
          children: [
            Row(
              children: [
                Expanded(
                  child: StatCard(
                    value: formatSteps(total),
                    unit: '',
                    caption: 'Всего за неделю',
                    accent: AppColors.accentMid,
                    icon: Icons.calendar_view_week_rounded,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: StatCard(
                    value: formatSteps(average),
                    unit: '',
                    caption: 'В среднем в день',
                    accent: AppColors.distance,
                    icon: Icons.show_chart_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('ПО ДНЯМ', style: AppText.label),
            const SizedBox(height: AppSpacing.md),
            for (final day in newestFirst) ...[
              _DayRow(day: day, goal: goal),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
        ),
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.day, required this.goal});

  final DayEntry day;
  final int goal;

  @override
  Widget build(BuildContext context) {
    final reached = day.steps >= goal;
    final tint = reached ? AppColors.gold : AppColors.accentMid;
    final progress = goal <= 0 ? 1.0 : (day.steps / goal).clamp(0.0, 1.0);

    return Semantics(
      label: '${day.fullName}, ${day.formattedDate}: '
          '${formatSteps(day.steps)} шагов',
      child: SurfaceCard(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 3,
                    backgroundColor: AppColors.stroke,
                    valueColor: AlwaysStoppedAnimation<Color>(tint),
                  ),
                  if (reached)
                    Icon(Icons.check_rounded, size: 16, color: tint),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    day.fullName,
                    style: AppText.title.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    day.formattedDate,
                    style: AppText.body.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
            Text(
              formatSteps(day.steps),
              style: AppText.statValue.copyWith(fontSize: 18, color: tint),
            ),
          ],
        ),
      ),
    );
  }
}
