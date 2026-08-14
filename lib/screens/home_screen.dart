import 'package:flutter/material.dart';

import '../models/day_stats.dart';
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
  /// that announces itself on every launch is noise.
  Future<void> _checkForUpdate() async {
    const checker = UpdateChecker();
    final result = await checker.check();
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
        builder: (_) => WeekDetailScreen(days: _week, goal: _snapshot.goal),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
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
                        'Разрешите распознавание активности, чтобы StepStep '
                        'считал шаги и показывал их на экране блокировки.',
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
                        'На этом устройстве нет аппаратного счётчика шагов, '
                        'поэтому считать шаги не получится.',
                  ),
                ),
              _Hero(snapshot: _snapshot, isLoading: _isLoading),
              const SizedBox(height: AppSpacing.xxl),
              _StatsGrid(snapshot: _snapshot),
              const SizedBox(height: AppSpacing.lg),
              _WeekSection(
                days: _week,
                goal: _snapshot.goal,
                onTap: _week.isEmpty ? null : _openWeekDetail,
              ),
            ],
          ),
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

    return Center(
      child: SizedBox(
        height: 300,
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
      ),
    );
  }
}

class _RingContents extends StatelessWidget {
  const _RingContents({required this.snapshot});

  final StepSnapshot snapshot;

  /// Widest the contents may get before they touch the ring's inner edge.
  /// Derived from the 300px ring at a 22px stroke, with margin for the glow.
  static const double _innerWidth = 205;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _innerWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // A six-figure day ("124 305") is wider than the ring's inside at the
          // display size, so the counter scales down rather than colliding
          // with the arc.
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

  /// Fixed rather than intrinsic: `IntrinsicHeight` around a `Row` whose child
  /// is itself a flex column forces an extra, expensive intrinsic layout pass
  /// on every rebuild — and the counter rebuilds on every sensor reading.
  static const double _gridHeight = 184;

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
    return SizedBox(
      height: _gridHeight,
      child: Row(
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
      ),
    );
  }
}

class _WeekSection extends StatelessWidget {
  const _WeekSection({required this.days, required this.goal, this.onTap});

  final List<DayEntry> days;
  final int goal;
  final VoidCallback? onTap;

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
              if (onTap != null) ...[
                const SizedBox(width: AppSpacing.xs),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: AppColors.textMuted,
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          WeekChart(days: days, goal: goal),
        ],
      ),
    );
  }
}
