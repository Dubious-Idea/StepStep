@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepstep/screens/home_screen.dart';
import 'package:stepstep/screens/month_screen.dart';
import 'package:stepstep/screens/onboarding_screen.dart';
import 'package:stepstep/screens/week_detail_screen.dart';
import 'package:stepstep/screens/year_screen.dart';
import 'package:stepstep/theme/app_theme.dart';

/// Fabricates a plausible day for every date the caller asked
/// `getHistoryRange` for, with a day key that actually matches what
/// [MonthScreen]/[WeekDetailScreen] look up — a mismatched key would just
/// render every cell as zero, which defeats the point of a visual snapshot.
List<Map<String, dynamic>> _syntheticRange(Map<dynamic, dynamic> arguments) {
  final start = DateTime.parse(arguments['start'] as String);
  final end = DateTime.parse(arguments['end'] as String);

  final days = <Map<String, dynamic>>[];
  var date = start;
  var i = 0;
  while (!date.isAfter(end)) {
    days.add({
      'dayKey':
          '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}',
      'steps': (i * 733) % 14000,
      'activeMinutes': 20 + (i % 6) * 12,
      'weekday': (date.weekday % 7) + 1,
    });
    date = date.add(const Duration(days: 1));
    i++;
  }
  return days;
}

/// Pixel snapshots of the two screens that carry the design.
///
/// Tagged `golden` and excluded from CI: these compare rendered pixels, which
/// differ between the machine that recorded them and Linux runners. Their job
/// is to catch an unintended visual change locally —
/// `flutter test --update-goldens test/golden` after a deliberate one.
void main() {
  const channel = MethodChannel('com.purrweb.stepstep/steps');

  const snapshot = <String, dynamic>{
    'steps': 8432,
    'goal': 12000,
    'activeMinutes': 84,
    'heightCm': 178,
    'weightKg': 74.0,
    'distanceKm': 6.213,
    'kcal': 288.4,
  };

  final week = [
    for (var i = 0; i < 7; i++)
      <String, dynamic>{
        'dayKey': '2026-07-2${i + 7}',
        'steps': [9120, 4310, 13400, 7020, 11250, 6180, 8432][i],
        'activeMinutes': 70 + i * 3,
        'weekday': (i + 2) % 7 + 1,
      },
  ];

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getHistoryRange') {
            return _syntheticRange(call.arguments as Map<dynamic, dynamic>);
          }
          return switch (call.method) {
            'getSnapshot' || 'refreshFromSensor' || 'saveProfile' => snapshot,
            'getHistory' => week,
            'hasStepSensor' => true,
            'isOnboarded' || 'isLiveNotificationEnabled' => true,
            'permissionStatus' || 'requestPermissions' => <String, dynamic>{
              'canCountSteps': true,
              'canShowNotification': true,
              'isPermanentlyDenied': false,
            },
            _ => null,
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  void usePhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
  }

  Widget wrap(Widget child) => MaterialApp(theme: buildAppTheme(), home: child);

  testWidgets('home screen', (tester) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(wrap(const HomeScreen()));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('home_screen.png'),
    );
  });

  testWidgets('onboarding, height step', (tester) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(wrap(OnboardingScreen(onFinished: () {})));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(OnboardingScreen),
      matchesGoldenFile('onboarding_height.png'),
    );
  });

  testWidgets('week detail', (tester) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(
      wrap(WeekDetailScreen(startDate: DateTime(2026, 7, 27), goal: 12000)),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(WeekDetailScreen),
      matchesGoldenFile('week_detail.png'),
    );
  });

  testWidgets('month screen', (tester) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(
      wrap(MonthScreen(year: 2026, month: 7, goal: 12000)),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MonthScreen),
      matchesGoldenFile('month_screen.png'),
    );
  });

  testWidgets('year screen', (tester) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(wrap(YearScreen(initialYear: 2026, goal: 12000)));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(YearScreen),
      matchesGoldenFile('year_screen.png'),
    );
  });
}
