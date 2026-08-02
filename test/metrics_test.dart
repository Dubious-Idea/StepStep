import 'package:flutter_test/flutter_test.dart';
import 'package:stepstep/models/profile.dart';
import 'package:stepstep/services/metrics.dart';

void main() {
  group('strideMeters', () {
    test('derives step length from height', () {
      // Arrange
      const heightCm = 175;

      // Act
      final stride = strideMeters(heightCm);

      // Assert
      expect(stride, closeTo(0.7245, 0.0001));
    });

    test('clamps implausible heights into the supported range', () {
      expect(strideMeters(10), strideMeters(Profile.minHeightCm));
      expect(strideMeters(400), strideMeters(Profile.maxHeightCm));
    });
  });

  group('distanceKm', () {
    test('multiplies steps by stride length', () {
      // Arrange
      const steps = 10000;
      const heightCm = 175;

      // Act
      final km = distanceKm(steps: steps, heightCm: heightCm);

      // Assert
      expect(km, closeTo(7.245, 0.001));
    });

    test('returns zero for a day without steps', () {
      expect(distanceKm(steps: 0, heightCm: 175), 0);
    });

    test('never returns a negative distance', () {
      expect(distanceKm(steps: -50, heightCm: 175), 0);
    });
  });

  group('activeKcal', () {
    test('matches the ACSM walking equation for a typical day', () {
      // Arrange — 10k steps, 175cm, 75kg, 100 active minutes => 72.45 m/min
      // net VO2 = 0.1 * 72.45 = 7.245 ml/kg/min
      // kcal/min = 7.245 * 75 / 200 = 2.7169
      // total    = 271.69 kcal

      // Act
      final kcal = activeKcal(
        steps: 10000,
        heightCm: 175,
        weightKg: 75,
        activeMinutes: 100,
      );

      // Assert
      expect(kcal, closeTo(271.69, 0.5));
    });

    test('scales linearly with body weight', () {
      final light = activeKcal(
        steps: 8000,
        heightCm: 170,
        weightKg: 50,
        activeMinutes: 80,
      );
      final heavy = activeKcal(
        steps: 8000,
        heightCm: 170,
        weightKg: 100,
        activeMinutes: 80,
      );

      expect(heavy, closeTo(light * 2, 0.01));
    });

    test('burns more for a taller person at the same step count', () {
      final short = activeKcal(
        steps: 8000,
        heightCm: 160,
        weightKg: 70,
        activeMinutes: 80,
      );
      final tall = activeKcal(
        steps: 8000,
        heightCm: 190,
        weightKg: 70,
        activeMinutes: 80,
      );

      expect(tall, greaterThan(short));
    });

    test('returns zero when no steps were taken', () {
      expect(
        activeKcal(steps: 0, heightCm: 175, weightKg: 75, activeMinutes: 0),
        0,
      );
    });

    test(
      'falls back to an assumed cadence when active minutes are missing',
      () {
        // Arrange — sensor gave steps but the minute buckets were lost.
        // Act
        final kcal = activeKcal(
          steps: 6000,
          heightCm: 175,
          weightKg: 75,
          activeMinutes: 0,
        );

        // Assert — 6000 steps at 100 spm => 60 min, still a sane number.
        expect(kcal, greaterThan(50));
        expect(kcal, lessThan(400));
      },
    );

    test('clamps absurdly high cadence to a plausible walking speed', () {
      // Arrange — 20k steps squeezed into 5 minutes is sensor noise.
      final noisy = activeKcal(
        steps: 20000,
        heightCm: 175,
        weightKg: 75,
        activeMinutes: 5,
      );
      final capped = activeKcal(
        steps: 20000,
        heightCm: 175,
        weightKg: 75,
        activeMinutes: 20000 * strideMeters(175) / maxSpeedMPerMin,
      );

      // Assert
      expect(noisy, closeTo(capped, 1.0));
    });

    test('clamps implausibly slow drift to a minimum walking speed', () {
      // Arrange — 200 steps spread over 8 hours is standing, not walking.
      final drift = activeKcal(
        steps: 200,
        heightCm: 175,
        weightKg: 75,
        activeMinutes: 480,
      );
      final floor = activeKcal(
        steps: 200,
        heightCm: 175,
        weightKg: 75,
        activeMinutes: 200 * strideMeters(175) / minSpeedMPerMin,
      );

      expect(drift, closeTo(floor, 0.5));
    });
  });

  group('goalProgress', () {
    test('reports the fraction of the daily goal reached', () {
      expect(goalProgress(steps: 6000, goal: 12000), closeTo(0.5, 0.0001));
    });

    test('caps at 1.0 once the goal is beaten', () {
      expect(goalProgress(steps: 30000, goal: 12000), 1.0);
    });

    test(
      'treats a non-positive goal as complete instead of dividing by zero',
      () {
        expect(goalProgress(steps: 100, goal: 0), 1.0);
      },
    );
  });

  group('formatSteps', () {
    test('groups thousands with a narrow space', () {
      expect(formatSteps(8432), '8 432');
      expect(formatSteps(432), '432');
      expect(formatSteps(1234567), '1 234 567');
    });
  });
}
