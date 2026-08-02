import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepstep/screens/home_screen.dart';
import 'package:stepstep/screens/onboarding_screen.dart';
import 'package:stepstep/theme/app_theme.dart';

/// Renders the real screens against a stubbed native side.
///
/// Layout is where this app can break without any test noticing — the ring,
/// the bento grid and the chart all size themselves from the viewport, so an
/// overflow only shows up on a device. `flutter_test` fails a test on any
/// overflow, which turns that into something CI can catch.
void main() {
  const channel = MethodChannel('com.purrweb.stepstep/steps');

  // A believable mid-afternoon: goal not yet reached, a full week behind it.
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
            'getHistoryEmpty' => <Map<String, dynamic>>[],
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

  /// Nothing Phone (1): 1080x2400 at 2.75x.
  void usePhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
  }

  Widget wrap(Widget child) => MaterialApp(theme: buildAppTheme(), home: child);

  testWidgets('home screen lays out today without overflowing', (tester) async {
    usePhoneViewport(tester);

    await tester.pumpWidget(wrap(const HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('StepStep'), findsOneWidget);
    expect(find.text('8\u202f432'), findsOneWidget);
    expect(find.text('ШАГОВ СЕГОДНЯ'), findsOneWidget);
    // Calories are the reason height and weight are collected — they must be
    // on screen, not behind a tap.
    expect(find.text('288'), findsOneWidget);
    expect(find.text('6.21 км'), findsOneWidget);
    expect(find.text('1 ч 24 мин'), findsOneWidget);
    expect(find.text('ещё 3\u202f568'), findsOneWidget);
  });

  testWidgets('home screen survives a small viewport', (tester) async {
    // 320dp-wide phones are the narrowest layout worth supporting; the bento
    // grid is the part most likely to break there.
    tester.view.physicalSize = const Size(640, 1280);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(const HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('8\u202f432'), findsOneWidget);
  });

  testWidgets('onboarding asks for height first', (tester) async {
    usePhoneViewport(tester);

    await tester.pumpWidget(wrap(OnboardingScreen(onFinished: () {})));
    await tester.pumpAndSettle();

    expect(find.text('Какой у вас рост?'), findsOneWidget);
    expect(find.text('Дальше'), findsOneWidget);
  });
}
