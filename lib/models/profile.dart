import 'dart:convert';

/// Body measurements the step-to-calorie model needs, plus the daily target.
///
/// Height drives stride length (and therefore distance and walking speed);
/// weight scales the energy cost of covering that distance.
class Profile {
  static const int minHeightCm = 100;
  static const int maxHeightCm = 250;
  static const double minWeightKg = 30;
  static const double maxWeightKg = 300;
  static const int minGoal = 1000;
  static const int maxGoal = 50000;

  static const int defaultHeightCm = 175;
  static const double defaultWeightKg = 70;
  static const int defaultGoal = 10000;

  const Profile({
    required this.heightCm,
    required this.weightKg,
    required this.goal,
  });

  const Profile.initial()
    : heightCm = defaultHeightCm,
      weightKg = defaultWeightKg,
      goal = defaultGoal;

  final int heightCm;
  final double weightKg;
  final int goal;

  /// A profile is only "set up" once the user has entered their own numbers,
  /// which onboarding records by writing a profile at all.
  bool get isValid =>
      heightCm >= minHeightCm &&
      heightCm <= maxHeightCm &&
      weightKg >= minWeightKg &&
      weightKg <= maxWeightKg &&
      goal >= minGoal &&
      goal <= maxGoal;

  Profile copyWith({int? heightCm, double? weightKg, int? goal}) => Profile(
    heightCm: heightCm ?? this.heightCm,
    weightKg: weightKg ?? this.weightKg,
    goal: goal ?? this.goal,
  );

  Map<String, dynamic> toMap() => {
    'heightCm': heightCm,
    'weightKg': weightKg,
    'goal': goal,
  };

  factory Profile.fromMap(Map<dynamic, dynamic> map) => Profile(
    heightCm: (map['heightCm'] as num?)?.toInt() ?? defaultHeightCm,
    weightKg: (map['weightKg'] as num?)?.toDouble() ?? defaultWeightKg,
    goal: (map['goal'] as num?)?.toInt() ?? defaultGoal,
  );

  String toJson() => jsonEncode(toMap());

  factory Profile.fromJson(String source) =>
      Profile.fromMap(jsonDecode(source) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) =>
      other is Profile &&
      other.heightCm == heightCm &&
      other.weightKg == weightKg &&
      other.goal == goal;

  @override
  int get hashCode => Object.hash(heightCm, weightKg, goal);

  @override
  String toString() =>
      'Profile(heightCm: $heightCm, weightKg: $weightKg, goal: $goal)';
}
