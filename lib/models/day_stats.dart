import '../services/metrics.dart';
import 'profile.dart';

/// Everything the UI shows for the current day, as computed natively.
///
/// The native side is the single source of truth: it owns the sensor, so the
/// widget, the lock-screen notification and this screen can never disagree.
class StepSnapshot {
  const StepSnapshot({
    required this.steps,
    required this.goal,
    required this.activeMinutes,
    required this.heightCm,
    required this.weightKg,
    required this.distanceKm,
    required this.kcal,
  });

  const StepSnapshot.empty()
    : steps = 0,
      goal = Profile.defaultGoal,
      activeMinutes = 0,
      heightCm = Profile.defaultHeightCm,
      weightKg = Profile.defaultWeightKg,
      distanceKm = 0,
      kcal = 0;

  final int steps;
  final int goal;
  final int activeMinutes;
  final int heightCm;
  final double weightKg;
  final double distanceKm;
  final double kcal;

  double get progress => goalProgress(steps: steps, goal: goal);

  bool get isGoalReached => steps >= goal;

  int get stepsLeft => (goal - steps).clamp(0, goal);

  Profile get profile =>
      Profile(heightCm: heightCm, weightKg: weightKg, goal: goal);

  factory StepSnapshot.fromMap(Map<dynamic, dynamic> map) => StepSnapshot(
    steps: (map['steps'] as num?)?.toInt() ?? 0,
    goal: (map['goal'] as num?)?.toInt() ?? Profile.defaultGoal,
    activeMinutes: (map['activeMinutes'] as num?)?.toInt() ?? 0,
    heightCm: (map['heightCm'] as num?)?.toInt() ?? Profile.defaultHeightCm,
    weightKg: (map['weightKg'] as num?)?.toDouble() ?? Profile.defaultWeightKg,
    distanceKm: (map['distanceKm'] as num?)?.toDouble() ?? 0,
    kcal: (map['kcal'] as num?)?.toDouble() ?? 0,
  );
}

/// One day of history, used by the week chart.
class DayEntry {
  const DayEntry({
    required this.dayKey,
    required this.steps,
    required this.activeMinutes,
    required this.weekday,
  });

  final String dayKey;
  final int steps;
  final int activeMinutes;

  /// `java.util.Calendar.DAY_OF_WEEK`: 1 = Sunday … 7 = Saturday.
  final int weekday;

  static const List<String> _shortNames = [
    'Вс',
    'Пн',
    'Вт',
    'Ср',
    'Чт',
    'Пт',
    'Сб',
  ];

  String get shortName => _shortNames[(weekday - 1).clamp(0, 6)];

  factory DayEntry.fromMap(Map<dynamic, dynamic> map) => DayEntry(
    dayKey: map['dayKey'] as String? ?? '',
    steps: (map['steps'] as num?)?.toInt() ?? 0,
    activeMinutes: (map['activeMinutes'] as num?)?.toInt() ?? 0,
    weekday: (map['weekday'] as num?)?.toInt() ?? 1,
  );
}
