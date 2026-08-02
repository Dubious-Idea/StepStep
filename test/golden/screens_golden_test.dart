@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepstep/screens/home_screen.dart';
import 'package:stepstep/screens/onboarding_screen.dart';
import 'package:stepstep/theme/app_theme.dart';

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
}
