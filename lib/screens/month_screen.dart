import 'package:flutter/material.dart';

import '../models/day_stats.dart';
import '../services/calendar_math.dart';
import '../services/step_bridge.dart';
import '../theme/tokens.dart';
import 'week_detail_screen.dart';

const List<String> _weekdayHeaders = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

/// Calendar grid for one month — tapping any day opens [WeekDetailScreen]
/// for the calendar week that day belongs to. The point of this screen is
/// picking a week, not inspecting a single day, so a day tap always resolves
/// to its Monday.
class MonthScreen extends StatefulWidget {
  const MonthScreen({
    super.key,
    required this.year,
    required this.month,
    required this.goal,
  });

  final int year;

  /// 1-12.
  final int month;
  final int goal;

  @override
  State<MonthScreen> createState() => _MonthScreenState();
}

class _MonthScreenState extends State<MonthScreen> {
  static const StepBridge _bridge = StepBridge();

  late int _year = widget.year;
  late int _month = widget.month;
  Map<String, DayEntry>? _byDayKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _byDayKey = null);
    final first = DateTime(_year, _month, 1);
    final last = DateTime(_year, _month + 1, 0);
    final days = await _bridge.historyRange(start: first, end: last);
    if (!mounted) return;
    setState(() => _byDayKey = {for (final d in days) d.dayKey: d});
  }

  void _shiftMonth(int delta) {
    final shifted = DateTime(_year, _month + delta, 1);
    _year = shifted.year;
    _month = shifted.month;
    _load();
  }

  void _openWeekFor(DateTime day) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            WeekDetailScreen(startDate: mondayOf(day), goal: widget.goal),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final byDayKey = _byDayKey;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${monthNamesNominative[_month - 1]} $_year',
          style: AppText.title.copyWith(fontSize: 17),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: 'Предыдущий месяц',
            onPressed: () => _shiftMonth(-1),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            tooltip: 'Следующий месяц',
            onPressed: () => _shiftMonth(1),
          ),
        ],
      ),
      body: SafeArea(
        child: byDayKey == null
            ? const Center(child: CircularProgressIndicator())
            : _MonthGrid(
                year: _year,
                month: _month,
                goal: widget.goal,
                byDayKey: byDayKey,
                onDayTap: _openWeekFor,
              ),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.year,
    required this.month,
    required this.goal,
    required this.byDayKey,
    required this.onDayTap,
  });

  final int year;
  final int month;
  final int goal;
  final Map<String, DayEntry> byDayKey;
  final ValueChanged<DateTime> onDayTap;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    // Monday-first grid: how many empty leading cells before day 1.
    final leading = first.weekday - 1;
    final totalCells = ((leading + daysInMonth + 6) ~/ 7) * 7;
    final today = DateTime.now();

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final h in _weekdayHeaders)
                Expanded(
                  child: Center(
                    child: Text(h, style: AppText.label.copyWith(fontSize: 10)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
              ),
              itemCount: totalCells,
              itemBuilder: (context, index) {
                final dayNumber = index - leading + 1;
                if (dayNumber < 1 || dayNumber > daysInMonth) {
                  return const SizedBox.shrink();
                }
                final date = DateTime(year, month, dayNumber);
                final entry = byDayKey[dayKeyOf(date)];
                final isToday =
                    date.year == today.year &&
                    date.month == today.month &&
                    date.day == today.day;

                return _DayCell(
                  dayNumber: dayNumber,
                  entry: entry,
                  goal: goal,
                  isToday: isToday,
                  onTap: () => onDayTap(date),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.dayNumber,
    required this.entry,
    required this.goal,
    required this.isToday,
    required this.onTap,
  });

  final int dayNumber;
  final DayEntry? entry;
  final int goal;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final steps = entry?.steps ?? 0;
    final reached = goal > 0 && steps >= goal;
    final hasSteps = steps > 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: isToday
                      ? Border.all(color: AppColors.accentMid, width: 1.5)
                      : null,
                ),
                child: Text(
                  '$dayNumber',
                  style: AppText.body.copyWith(
                    fontSize: 13,
                    color: isToday
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              SizedBox(
                height: 4,
                width: 4,
                child: hasSteps
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: reached ? AppColors.gold : AppColors.accentMid,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
