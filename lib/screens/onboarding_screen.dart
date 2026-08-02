import 'package:flutter/material.dart';

import '../models/profile.dart';
import '../services/metrics.dart';
import '../services/permissions.dart';
import '../services/step_bridge.dart';
import '../theme/tokens.dart';
import '../widgets/primary_button.dart';
import '../widgets/ruler_picker.dart';

/// Three questions, one per screen: height, weight, daily goal.
///
/// Height and weight are not optional politeness — the calorie model is built
/// from them (height sets stride length and therefore walking speed, weight
/// scales the energy cost), so each step says why it is asking.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const StepBridge _bridge = StepBridge();
  static const StepPermissions _permissions = StepPermissions();
  static const List<int> _goalPresets = [6000, 8000, 10000, 12000, 15000];

  final PageController _pages = PageController();

  int _index = 0;
  double _heightCm = Profile.defaultHeightCm.toDouble();
  double _weightKg = Profile.defaultWeightKg;
  int _goal = Profile.defaultGoal;
  bool _isSaving = false;

  static const int _stepCount = 3;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_index < _stepCount - 1) {
      _pages.nextPage(duration: AppDuration.normal, curve: AppCurves.outExpo);
      return;
    }
    _finish();
  }

  Future<void> _finish() async {
    setState(() => _isSaving = true);

    // Ask before saving: the native side starts the live notification as soon
    // as a profile lands, and starting it without the permission is what
    // Android rejects outright.
    await _permissions.request();
    await _bridge.saveProfile(
      Profile(heightCm: _heightCm.round(), weightKg: _weightKg, goal: _goal),
    );
    await _bridge.startTracking();

    if (!mounted) return;
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _ProgressDots(index: _index, total: _stepCount),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _index = i),
                children: [
                  _Step(
                    title: 'Какой у вас рост?',
                    subtitle:
                        'По росту считается длина шага — от неё зависят '
                        'дистанция и скорость ходьбы.',
                    readout: MeasureReadout(value: _heightCm, unit: 'см'),
                    picker: RulerPicker(
                      value: _heightCm,
                      min: Profile.minHeightCm.toDouble(),
                      max: Profile.maxHeightCm.toDouble(),
                      majorEvery: 10,
                      onChanged: (v) => setState(() => _heightCm = v),
                    ),
                    hint:
                        'Длина шага ≈ '
                        '${strideMeters(_heightCm.round()).toStringAsFixed(2)} м',
                  ),
                  _Step(
                    title: 'И вес?',
                    subtitle:
                        'Вес определяет, во сколько калорий обходится '
                        'пройденное расстояние.',
                    readout: MeasureReadout(
                      value: _weightKg,
                      unit: 'кг',
                      fractionDigits: 0,
                    ),
                    picker: RulerPicker(
                      value: _weightKg,
                      min: Profile.minWeightKg,
                      max: 200,
                      majorEvery: 5,
                      onChanged: (v) => setState(() => _weightKg = v),
                    ),
                    hint:
                        '10 000 шагов ≈ '
                        '${activeKcal(steps: 10000, heightCm: _heightCm.round(), weightKg: _weightKg, activeMinutes: 100).round()} ккал',
                  ),
                  _GoalStep(
                    goal: _goal,
                    presets: _goalPresets,
                    onChanged: (v) => setState(() => _goal = v),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                AppSpacing.lg,
                AppSpacing.screenPadding,
                AppSpacing.xl,
              ),
              child: PrimaryButton(
                label: _index == _stepCount - 1 ? 'Начать' : 'Дальше',
                isBusy: _isSaving,
                onPressed: _isSaving ? null : _next,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.title,
    required this.subtitle,
    required this.readout,
    required this.picker,
    required this.hint,
  });

  final String title;
  final String subtitle;
  final Widget readout;
  final Widget picker;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.xxl),
          Text(title, style: AppText.display.copyWith(fontSize: 34)),
          const SizedBox(height: AppSpacing.md),
          Text(subtitle, style: AppText.body),
          const Spacer(),
          readout,
          const SizedBox(height: AppSpacing.lg),
          picker,
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: Text(
              hint,
              style: AppText.labelBright.copyWith(
                color: AppColors.accentMid,
                letterSpacing: 0.6,
              ),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _GoalStep extends StatelessWidget {
  const _GoalStep({
    required this.goal,
    required this.presets,
    required this.onChanged,
  });

  final int goal;
  final List<int> presets;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.xxl),
          Text('Цель на день', style: AppText.display.copyWith(fontSize: 34)),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Кольцо на главном экране и на экране блокировки заполняется '
            'до этой цифры. Её всегда можно поменять.',
            style: AppText.body,
          ),
          const Spacer(),
          Center(
            child: MeasureReadout(value: goal.toDouble(), unit: 'шагов'),
          ),
          const SizedBox(height: AppSpacing.xl),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final preset in presets)
                _GoalChip(
                  value: preset,
                  isSelected: preset == goal,
                  onTap: () => onChanged(preset),
                ),
            ],
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _GoalChip extends StatelessWidget {
  const _GoalChip({
    required this.value,
    required this.isSelected,
    required this.onTap,
  });

  final int value;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        splashColor: AppColors.accentMid.withValues(alpha: 0.12),
        child: AnimatedContainer(
          duration: AppDuration.fast,
          curve: AppCurves.inOut,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.accentMid.withValues(alpha: 0.14)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: isSelected ? AppColors.accentMid : AppColors.stroke,
            ),
          ),
          child: Text(
            formatSteps(value),
            style: AppText.labelBright.copyWith(
              fontSize: 13,
              letterSpacing: 0.2,
              color: isSelected ? AppColors.accentMid : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.index, required this.total});

  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < total; i++)
            AnimatedContainer(
              duration: AppDuration.normal,
              curve: AppCurves.outExpo,
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              width: i == index ? 26 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == index ? AppColors.accentStart : AppColors.stroke,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
        ],
      ),
    );
  }
}
