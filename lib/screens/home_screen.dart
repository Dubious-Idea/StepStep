import 'package:flutter/material.dart';

import '../models/day_stats.dart';
import '../services/calendar_math.dart';
import '../services/metrics.dart';
import '../services/permissions.dart';
import '../services/step_bridge.dart';
import '../services/update_checker.dart';
import '../theme/tokens.dart';
import '../widgets/animated_counter.dart';
import '../widgets/notice_banner.dart';
import '../widgets/stat_card.dart';
import '../widgets/step_ring.dart';
import '../widgets/update_dialog.dart';
import '../widgets/week_chart.dart';
import 'profile_screen.dart';
import 'week_detail_screen.dart';
import 'year_screen.dart';

/// The one screen the app really is: today's ring, what it cost in calories,
/// and how the week is going.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const StepBridge _bridge = StepBridge();
  static const StepPermissions _permissions = StepPermissions();

  StepSnapshot _snapshot = const StepSnapshot.empty();
  List<DayEntry> _week = const [];
  bool _hasSensor = true;
  bool _canCountSteps = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _checkForUpdate();
  }

  /// The app ships outside any store, so this is the only way a new build
  /// reaches the user. Silent on failure and on "up to date" — an update check
  /// that announces itself on every launch is noise. Throttled to once a day
  /// and can be turned off entirely from the profile screen; the manual
  /// "Проверить обновления" button there bypasses both.
  Future<void> _checkForUpdate() async {
    const checker = UpdateChecker();
    if (!await checker.isAutoCheckEnabled() || !mounted) return;
    if (!await checker.isAutoCheckDue() || !mounted) return;

    final result = await checker.check();
    await checker.recordAutoCheck();
    if (result is! UpdateAvailable || !mounted) return;

    final skipped = await checker.skippedVersion();
    if (skipped == result.update.version || !mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => UpdateDialog(
        update: result.update,
        onInstall: () {
          Navigator.of(dialogContext).pop();
          checker.openUrl(result.update.downloadUrl);
        },
        onSkip: () {
          Navigator.of(dialogContext).pop();
          checker.skipVersion(result.update.version);
        },
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Steps taken while the app was backgrounded live in the hardware counter,
    // so coming back is exactly when we need to re-read it.
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _bridge.refreshFromSensor(),
      _bridge.history(days: 7),
      _bridge.hasStepSensor(),
      _permissions.status(),
    ]);

    if (!mounted) return;
    setState(() {
      _snapshot = results[0] as StepSnapshot;
      _week = results[1] as List<DayEntry>;
      _hasSensor = results[2] as bool;
      _canCountSteps = (results[3] as PermissionOutcome).canCountSteps;
      _isLoading = false;
    });
  }

  Future<void> _openProfile() async {
    final updated = await Navigator.of(context).push<StepSnapshot>(
      MaterialPageRoute(builder: (_) => ProfileScreen(snapshot: _snapshot)),
    );
    if (updated != null && mounted) setState(() => _snapshot = updated);
    await _load();
  }

  void _openWeekDetail() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WeekDetailScreen(
          startDate: mondayOf(DateTime.now()),
          goal: _snapshot.goal,
        ),
      ),
    );
  }

  void _openCalendar() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            YearScreen(initialYear: DateTime.now().year, goal: _snapshot.goal),
      ),
    );
  }

  Future<void> _requestPermission() async {
    final outcome = await _permissions.request();
    if (outcome.canCountSteps) {
      await _bridge.startTracking();
    } else if (outcome.isPermanentlyDenied) {
      await _permissions.openSettings();
    }
    await _load();
  }

  /// Rough height of whichever notice banner is showing, including its own
  /// trailing gap — used only to size the ring and grid below, so it does
  /// not need to be exact, just not wildly off.
  double _bannerHeightEstimate() {
    if (_canCountSteps && _hasSensor) return 0;
    // The permission banner carries an extra action button the sensor
    // banner doesn't.
    return _canCountSteps ? 130 : 170;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // StepRing sizes itself via its own LayoutBuilder, which cannot
            // answer intrinsic-dimension queries — that rules out Expanded
            // inside a sliver that probes intrinsics (SliverFillRemaining)
            // to make the ring "fill the rest of the screen". Instead the
            // available height is measured once, up front, and the ring and
            // grid get explicit computed heights, leaving everything else at
            // its natural size. The budget below is calibrated against the
            // reference viewport in test/home_screen_render_test.dart, where
            // it lands within a few pixels of the old fixed 300/184 — on a
            // shorter screen it shrinks instead of pushing the week card off
            // the bottom into a sliver of scroll.
            const fixedChrome =
                AppSpacing.lg + // ListView top padding
                48 + // header row (IconButton's default tap target)
                AppSpacing.xl + // gap under header
                AppSpacing.xxl + // gap between ring and grid
                AppSpacing.lg + // gap between grid and week card
                190 + // week card (SurfaceCard + WeekChart), estimated
                AppSpacing.section; // ListView bottom padding

            final remainder =
                constraints.maxHeight - fixedChrome - _bannerHeightEstimate();
            // 230 keeps the ring's inner content — specifically the goal
            // pill's icon + text row — wide enough not to overflow; below
            // that the ring shrinks faster than its own contents do.
            final heroHeight = (remainder * 0.62).clamp(230.0, 340.0);
            // 184 was the old fixed height StatCard's content was designed
            // against — below that its icon/value/footnote stack overflows,
            // so this floor is not just a stylistic minimum.
            final gridHeight = (remainder * 0.38).clamp(184.0, 210.0);

            return RefreshIndicator(
              onRefresh: _load,
              color: AppColors.accentMid,
              backgroundColor: AppColors.surface,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding,
                  AppSpacing.lg,
                  AppSpacing.screenPadding,
                  AppSpacing.section,
                ),
                children: [
                  _Header(onSettings: _openProfile),
                  const SizedBox(height: AppSpacing.xl),
                  if (!_canCountSteps)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                      child: NoticeBanner(
                        icon: Icons.lock_outline,
                        title: 'Нет доступа к шагам',
                        message:
                            'Разрешите распознавание активности, чтобы '
                            'StepStep считал шаги и показывал их на '
                            'экране блокировки.',
                        actionLabel: 'Разрешить',
                        onAction: _requestPermission,
                      ),
                    )
                  else if (!_hasSensor)
                    const Padding(
                      padding: EdgeInsets.only(bottom: AppSpacing.lg),
                      child: NoticeBanner(
                        icon: Icons.sensors_off_outlined,
                        title: 'Датчик шагов не найден',
                        message:
                            'На этом устройстве нет аппаратного счётчика '
                            'шагов, поэтому считать шаги не получится.',
                      ),
                    ),
                  SizedBox(
                    height: heroHeight,
                    child: _Hero(snapshot: _snapshot, isLoading: _isLoading),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  SizedBox(
                    height: gridHeight,
                    child: _StatsGrid(snapshot: _snapshot),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _WeekSection(
                    days: _week,
                    goal: _snapshot.goal,
                    onTap: _week.isEmpty ? null : _openWeekDetail,
                    onOpenCalendar: _openCalendar,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: AppColors.accentStart,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: AppColors.accentStart, blurRadius: 10),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Text('StepStep', style: AppText.title.copyWith(letterSpacing: -0.5)),
        const Spacer(),
        IconButton(
          onPressed: onSettings,
          icon: const Icon(Icons.tune_rounded),
          color: AppColors.textSecondary,
          tooltip: 'Профиль и цель',
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.snapshot, required this.isLoading});

  final StepSnapshot snapshot;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final animate = !MediaQuery.disableAnimationsOf(context);

    // No fixed size here on purpose: the parent Expanded hands this exactly
    // the height the current screen has room for, and StepRing's own
    // LayoutBuilder already sizes itself to the shorter side of whatever
    // box it gets.
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: isLoading ? 0 : snapshot.progress),
        duration: animate ? AppDuration.ring : Duration.zero,
        curve: AppCurves.outExpo,
        builder: (context, progress, _) => StepRing(
          progress: progress,
          goalReached: snapshot.isGoalReached,
          strokeWidth: 22,
          child: _RingContents(snapshot: snapshot),
        ),
      ),
    );
  }
}

class _RingContents extends StatelessWidget {
  const _RingContents({required this.snapshot});

  final StepSnapshot snapshot;

  /// Fraction of the ring's own diameter the contents may use before they
  /// touch its inner edge — ring size is no longer fixed, so this scales
  /// with whatever diameter StepRing actually ends up at (originally tuned
  /// at a 300px ring with a 22px stroke: 205 / 300 ≈ 0.68).
  static const double _innerWidthFraction = 0.68;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          width: constraints.maxWidth * _innerWidthFraction,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // A six-figure day ("124 305") is wider than the ring's inside
              // at the display size, so the counter scales down rather than
              // colliding with the arc.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: AnimatedCounter(
                  value: snapshot.steps,
                  style: AppText.display,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text('ШАГОВ СЕГОДНЯ', style: AppText.label),
              const SizedBox(height: AppSpacing.lg),
              _GoalPill(snapshot: snapshot),
            ],
          ),
        );
      },
    );
  }
}

class _GoalPill extends StatelessWidget {
  const _GoalPill({required this.snapshot});

  final StepSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final reached = snapshot.isGoalReached;
    final tint = reached ? AppColors.gold : AppColors.accentMid;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: tint.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            reached ? Icons.check_circle_rounded : Icons.flag_outlined,
            size: 13,
            color: tint,
          ),
          const SizedBox(width: 6),
          Text(
            reached
                ? 'Цель выполнена'
                : 'ещё ${formatSteps(snapshot.stepsLeft)}',
            style: AppText.labelBright.copyWith(
              color: tint,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bento grid: calories get the large tile because they are the reason the
/// user entered height and weight at all; distance and active time support it.
class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.snapshot});

  final StepSnapshot snapshot;

  /// Says what the number is made of, so the figure reads as a calculation
  /// rather than a guess — and explains why the app asked for height and
  /// weight in the first place.
  static String _caloriesFootnote(StepSnapshot snapshot) {
    if (snapshot.steps == 0) {
      return 'по росту ${snapshot.heightCm} см '
          'и весу ${snapshot.weightKg.round()} кг';
    }
    return 'за ${formatActiveTime(snapshot.activeMinutes.toDouble())} движения';
  }

  @override
  Widget build(BuildContext context) {
    // No SizedBox here either — the parent Expanded already hands this a
    // tight height, and CrossAxisAlignment.stretch fills it.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 5,
          child: StatCard(
            value: '${snapshot.kcal.round()}',
            unit: 'ккал',
            caption: 'Сожжено',
            accent: AppColors.calories,
            icon: Icons.local_fire_department_rounded,
            emphasis: StatEmphasis.large,
            footnote: _caloriesFootnote(snapshot),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          flex: 4,
          child: Column(
            children: [
              Expanded(
                child: StatCard(
                  value: formatDistance(snapshot.distanceKm),
                  unit: '',
                  caption: 'Дистанция',
                  accent: AppColors.distance,
                  icon: Icons.timeline_rounded,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: StatCard(
                  value: formatActiveTime(snapshot.activeMinutes.toDouble()),
                  unit: '',
                  caption: 'В движении',
                  accent: AppColors.activeTime,
                  icon: Icons.bolt_rounded,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WeekSection extends StatelessWidget {
  const _WeekSection({
    required this.days,
    required this.goal,
    required this.onOpenCalendar,
    this.onTap,
  });

  final List<DayEntry> days;
  final int goal;
  final VoidCallback? onTap;
  final VoidCallback onOpenCalendar;

  @override
  Widget build(BuildContext context) {
    final total = days.fold<int>(0, (sum, d) => sum + d.steps);
    final average = days.isEmpty ? 0 : total ~/ days.length;

    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('НЕДЕЛЯ', style: AppText.label),
              const SizedBox(width: AppSpacing.md),
              // Flexible, not Spacer: on a 320dp screen the average line is
              // wider than the room left over, and a Spacer would push it off
              // the card instead of letting it ellipsize.
              Expanded(
                child: Text(
                  'в среднем ${formatSteps(average)}',
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body.copyWith(fontSize: 12),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _CalendarButton(onTap: onOpenCalendar),
              if (onTap != null)
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: AppColors.textMuted,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          WeekChart(days: days, goal: goal),
        ],
      ),
    );
  }
}

/// Opens the year/month browser. A separate tap target nested inside the
/// week card's own [SurfaceCard.onTap] — Flutter resolves the inner
/// [InkWell] first, so this claims its tap before it reaches the card.
class _CalendarButton extends StatelessWidget {
  const _CalendarButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: const Padding(
          padding: EdgeInsets.all(4),
          child: Icon(
            Icons.calendar_month_rounded,
            size: 16,
            color: AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}
