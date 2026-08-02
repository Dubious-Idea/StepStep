import 'dart:math' as math;

import '../models/profile.dart';

/// Step length as a fraction of body height. 0.414 is the commonly used
/// average for adult walking; running lengthens it, but a pedometer cannot
/// tell the difference reliably, so one ratio is honest enough.
const double strideToHeightRatio = 0.414;

/// Plausible walking speeds in metres per minute. Anything outside this band
/// is sensor noise (a phone shaken in a bag) or standing still with drift,
/// so speed is clamped before it reaches the energy equation.
const double minSpeedMPerMin = 40.0; // ~2.4 km/h — a slow amble
const double maxSpeedMPerMin = 150.0; // ~9 km/h — a brisk jog

/// Used when the per-minute buckets are unavailable (fresh install, restored
/// backup) but a total step count survived.
const double fallbackCadenceStepsPerMin = 100.0;

/// Energy equivalent of oxygen: ~5 kcal per litre of O2 consumed.
/// Combined with the ml/kg/min units of VO2 this gives the /200 divisor.
const double _kcalPerMinDivisor = 200.0;

/// Net oxygen cost of horizontal walking per m/min of speed (ACSM equation).
const double _acsmHorizontalVo2Factor = 0.1;

/// Step length in metres for a given body height.
double strideMeters(int heightCm) {
  final clamped = heightCm.clamp(Profile.minHeightCm, Profile.maxHeightCm);
  return clamped * strideToHeightRatio / 100;
}

/// Distance covered by [steps] for someone [heightCm] tall, in kilometres.
double distanceKm({required int steps, required int heightCm}) {
  if (steps <= 0) return 0;
  return steps * strideMeters(heightCm) / 1000;
}

/// Active (net-of-resting) calories burned by walking, in kcal.
///
/// Uses the ACSM walking equation: the oxygen cost above rest is
/// `0.1 ml/kg/min` per `m/min` of horizontal speed. Speed comes from the
/// distance the steps covered divided by the minutes spent actually moving,
/// which is why [activeMinutes] matters as much as the step total — 10 000
/// steps taken briskly cost more than the same steps spread over a whole day.
double activeKcal({
  required int steps,
  required int heightCm,
  required double weightKg,
  required double activeMinutes,
}) {
  if (steps <= 0) return 0;

  final minutes = activeMinutes > 0
      ? activeMinutes
      : steps / fallbackCadenceStepsPerMin;
  final metres = steps * strideMeters(heightCm);
  final speed = (metres / minutes).clamp(minSpeedMPerMin, maxSpeedMPerMin);

  // Re-derive duration from the clamped speed so that energy stays consistent
  // with the speed we actually believe, instead of mixing a capped speed with
  // an implausible duration.
  final effectiveMinutes = metres / speed;

  final netVo2 = _acsmHorizontalVo2Factor * speed; // ml/kg/min above rest
  final kcalPerMin = netVo2 * weightKg / _kcalPerMinDivisor;
  return kcalPerMin * effectiveMinutes;
}

/// Fraction of the daily goal reached, clamped to `0.0..1.0`.
double goalProgress({required int steps, required int goal}) {
  if (goal <= 0) return 1.0;
  return (steps / goal).clamp(0.0, 1.0);
}

/// Formats a step count with narrow no-break spaces between thousands,
/// e.g. `8432` -> `8 432`.
String formatSteps(int steps) {
  final digits = steps.abs().toString();
  final buffer = StringBuffer(steps < 0 ? '-' : '');

  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Formats distance for display: metres below 1 km, otherwise kilometres.
String formatDistance(double km) {
  if (km < 1) return '${(km * 1000).round()} м';
  return '${km.toStringAsFixed(km < 10 ? 2 : 1)} км';
}

/// Formats a duration in minutes as `1 ч 12 мин` / `48 мин`.
String formatActiveTime(double minutes) {
  final total = minutes.round();
  if (total < 60) return '$total мин';
  final hours = total ~/ 60;
  final rest = total % 60;
  return rest == 0 ? '$hours ч' : '$hours ч $rest мин';
}

/// Largest value in [values], never below [floor] — keeps chart bars from
/// exploding when a week only contains a handful of steps.
int chartCeiling(Iterable<int> values, {int floor = 1000}) =>
    math.max(floor, values.fold(0, math.max));
