import 'package:flutter/material.dart';

import '../models/day_stats.dart';
import '../services/calendar_math.dart';
import '../services/metrics.dart';
import '../services/step_bridge.dart';
import '../theme/tokens.dart';
import '../widgets/stat_card.dart';

/// Day-by-day breakdown for the calendar week starting on [startDate]
/// (a Monday) — reached either from the home screen's week card (today's
/// week) or by picking a day in [MonthScreen] (that day's week).
///
/// Loads its own data by date range rather than taking a pre-fetched list,
/// so it works the same regardless of which screen opened it, and the user
/// can page to any other week from here with the arrows in the app bar.
class WeekDetailScreen extends StatefulWidget {
  const WeekDetailScreen({
    super.key,
    required this.startDate,
    required this.goal,
  });

  /// Monday of the week to show.
  final DateTime startDate;
  final int goal;

  @override
  State<WeekDetailScreen> createState() => _WeekDetailScreenState();
}

class _WeekDetailScreenState extends State<WeekDetailScreen> {
  static const StepBridge _bridge = StepBridge();

  late DateTime _startDate = widget.startDate;
  List<DayEntry>? _days;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _days = null);
    final days = await _bridge.historyRange(
      start: _startDate,
      end: _startDate.add(const Duration(days: 6)),
    );
    if (!mounted) return;
    setState(() => _days = days);
  }

  void _shiftWeek(int deltaWeeks) {
    _startDate = _startDate.add(Duration(days: 7 * deltaWeeks));
    _load();
  }

  String get _rangeLabel {
    final end = _startDate.add(const Duration(days: 6));
    final startMonth = monthNamesGenitive[_startDate.month - 1];
    if (_startDate.month == end.month && _startDate.year == end.year) {
      return '${_startDate.day}–${end.day} $startMonth ${end.year}';
    }
    final endMonth = monthNamesGenitive[end.month - 1];
    if (_startDate.year == end.year) {
      return '${_startDate.day} $startMonth – ${end.day} $endMonth ${end.year}';
    }
    return '${_startDate.day} $startMonth ${_startDate.year} – '
        '${end.day} $endMonth ${end.year}';
  }

  @override
  Widget build(BuildContext context) {
    final days = _days;

    return Scaffold(
      appBar: AppBar(
        title: Text(_rangeLabel, style: AppText.title.copyWith(fontSize: 17)),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: 'Предыдущая неделя',
            onPressed: () => _shiftWeek(-1),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            tooltip: 'Следующая неделя',
            onPressed: () => _shiftWeek(1),
          ),
        ],
      ),
      body: SafeArea(
        child: days == null
            ? const Center(child: CircularProgressIndicator())
            : _WeekBody(days: days, goal: widget.goal),
      ),
    );
  }
}

class _WeekBody extends StatelessWidget {
  const _WeekBody({required this.days, required this.goal});

  final List<DayEntry> days;
  final int goal;

  @override
  Widget build(BuildContext context) {
    final total = days.fold<int>(0, (sum, d) => sum + d.steps);
    final average = days.isEmpty ? 0 : total ~/ days.length;

    return ListView(
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
        for (final day in days) ...[
          _DayRow(day: day, goal: goal),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
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
      label:
          '${day.fullName}, ${day.formattedDate}: '
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
                  if (reached) Icon(Icons.check_rounded, size: 16, color: tint),
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
