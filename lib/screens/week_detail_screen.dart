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
/// Weeks page left/right through a [PageView] anchored on an arbitrarily
/// large centre index, so both a swipe and the app bar arrows drive the same
/// animated transition and neither end ever runs out of pages.
class WeekDetailScreen extends StatefulWidget {
  const WeekDetailScreen({
    super.key,
    required this.startDate,
    required this.goal,
  });

  /// Monday of the week to show first.
  final DateTime startDate;
  final int goal;

  @override
  State<WeekDetailScreen> createState() => _WeekDetailScreenState();
}

class _WeekDetailScreenState extends State<WeekDetailScreen> {
  /// Large enough that no amount of swiping in either direction runs out —
  /// at 7 days per page that is roughly 900 years of weeks each way.
  static const int _centerPage = 50000;

  late final PageController _pageController = PageController(
    initialPage: _centerPage,
  );
  int _currentPage = _centerPage;

  DateTime _startDateForPage(int page) =>
      widget.startDate.add(Duration(days: 7 * (page - _centerPage)));

  void _shiftWeek(int deltaWeeks) {
    _pageController.animateToPage(
      _currentPage + deltaWeeks,
      duration: AppDuration.normal,
      curve: AppCurves.outExpo,
    );
  }

  String _rangeLabelFor(DateTime startDate) {
    final end = startDate.add(const Duration(days: 6));
    final startMonth = monthNamesGenitive[startDate.month - 1];
    if (startDate.month == end.month && startDate.year == end.year) {
      return '${startDate.day}–${end.day} $startMonth ${end.year}';
    }
    final endMonth = monthNamesGenitive[end.month - 1];
    if (startDate.year == end.year) {
      return '${startDate.day} $startMonth – ${end.day} $endMonth ${end.year}';
    }
    return '${startDate.day} $startMonth ${startDate.year} – '
        '${end.day} $endMonth ${end.year}';
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _rangeLabelFor(_startDateForPage(_currentPage)),
          style: AppText.title.copyWith(fontSize: 17),
        ),
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
        child: PageView.builder(
          controller: _pageController,
          onPageChanged: (page) => setState(() => _currentPage = page),
          itemBuilder: (context, page) => _WeekPage(
            key: ValueKey(page),
            startDate: _startDateForPage(page),
            goal: widget.goal,
          ),
        ),
      ),
    );
  }
}

/// One page's worth of data, loaded on demand — [PageView.builder] keeps a
/// handful of neighbouring pages alive, so each fetches independently rather
/// than the parent screen owning one big cache.
class _WeekPage extends StatefulWidget {
  const _WeekPage({super.key, required this.startDate, required this.goal});

  final DateTime startDate;
  final int goal;

  @override
  State<_WeekPage> createState() => _WeekPageState();
}

class _WeekPageState extends State<_WeekPage> {
  static const StepBridge _bridge = StepBridge();

  List<DayEntry>? _days;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final days = await _bridge.historyRange(
      start: widget.startDate,
      end: widget.startDate.add(const Duration(days: 6)),
    );
    if (!mounted) return;
    setState(() => _days = days);
  }

  @override
  Widget build(BuildContext context) {
    final days = _days;
    return days == null
        ? const Center(child: CircularProgressIndicator())
        : _WeekBody(days: days, goal: widget.goal);
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
