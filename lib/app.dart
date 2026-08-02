import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/step_bridge.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';

class StepStepApp extends StatelessWidget {
  const StepStepApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StepStep',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const _Root(),
    );
  }
}

/// Decides between onboarding and the counter.
///
/// The answer lives natively (the same store the widget and the notification
/// read), so this is an async gate rather than a local flag.
class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  static const StepBridge _bridge = StepBridge();

  bool? _isOnboarded;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final onboarded = await _bridge.isOnboarded();
    if (mounted) setState(() => _isOnboarded = onboarded);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppDuration.normal,
      switchInCurve: AppCurves.outExpo,
      child: switch (_isOnboarded) {
        // Blank rather than a spinner: the check resolves in a frame or two,
        // and a flashing spinner would be louder than the wait.
        null => const ColoredBox(
          color: AppColors.background,
          child: SizedBox.expand(),
        ),
        false => OnboardingScreen(
          onFinished: () => setState(() => _isOnboarded = true),
        ),
        true => const HomeScreen(),
      },
    );
  }
}
