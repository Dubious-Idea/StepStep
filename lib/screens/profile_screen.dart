import 'package:flutter/material.dart';

import '../models/day_stats.dart';
import '../models/profile.dart';
import '../services/metrics.dart';
import '../services/permissions.dart';
import '../services/step_bridge.dart';
import '../theme/tokens.dart';
import '../widgets/primary_button.dart';
import '../widgets/ruler_picker.dart';
import '../widgets/stat_card.dart';

/// Editing the same three numbers onboarding asked for, plus the switch for
/// the lock-screen notification.
///
/// Pops with the fresh [StepSnapshot] so the home screen shows recalculated
/// calories the instant weight changes, without waiting for a reload.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.snapshot});

  final StepSnapshot snapshot;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const StepBridge _bridge = StepBridge();
  static const StepPermissions _permissions = StepPermissions();
  static const List<int> _goalPresets = [6000, 8000, 10000, 12000, 15000];

  late double _heightCm = widget.snapshot.heightCm.toDouble();
  late double _weightKg = widget.snapshot.weightKg;
  late int _goal = widget.snapshot.goal;

  bool _liveNotification = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadNotificationSetting();
  }

  Future<void> _loadNotificationSetting() async {
    final enabled = await _bridge.isLiveNotificationEnabled();
    if (mounted) setState(() => _liveNotification = enabled);
  }

  bool get _hasChanges =>
      _heightCm.round() != widget.snapshot.heightCm ||
      _weightKg != widget.snapshot.weightKg ||
      _goal != widget.snapshot.goal;

  Future<void> _toggleNotification(bool enabled) async {
    setState(() => _liveNotification = enabled);

    if (enabled) {
      final outcome = await _permissions.request();
      if (!outcome.canShowNotification && mounted) {
        setState(() => _liveNotification = false);
        _showMessage('Разрешите уведомления в настройках системы');
        return;
      }
    }
    await _bridge.setLiveNotificationEnabled(enabled);
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);

    final updated = await _bridge.saveProfile(
      Profile(heightCm: _heightCm.round(), weightKg: _weightKg, goal: _goal),
    );

    if (!mounted) return;
    Navigator.of(context).pop(updated);
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          text,
          style: AppText.body.copyWith(color: AppColors.textPrimary),
        ),
        backgroundColor: AppColors.surfaceRaised,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Профиль')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenPadding,
                ),
                children: [
                  _Field(
                    label: 'Рост',
                    readout: MeasureReadout(value: _heightCm, unit: 'см'),
                    child: RulerPicker(
                      value: _heightCm,
                      min: Profile.minHeightCm.toDouble(),
                      max: Profile.maxHeightCm.toDouble(),
                      majorEvery: 10,
                      height: 76,
                      onChanged: (v) => setState(() => _heightCm = v),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _Field(
                    label: 'Вес',
                    readout: MeasureReadout(value: _weightKg, unit: 'кг'),
                    child: RulerPicker(
                      value: _weightKg,
                      min: Profile.minWeightKg,
                      max: 200,
                      majorEvery: 5,
                      height: 76,
                      onChanged: (v) => setState(() => _weightKg = v),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text('ЦЕЛЬ НА ДЕНЬ', style: AppText.label),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final preset in _goalPresets)
                        _Chip(
                          label: formatSteps(preset),
                          isSelected: preset == _goal,
                          onTap: () => setState(() => _goal = preset),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _NotificationToggle(
                    value: _liveNotification,
                    onChanged: _toggleNotification,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _Preview(heightCm: _heightCm.round(), weightKg: _weightKg),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                AppSpacing.md,
                AppSpacing.screenPadding,
                AppSpacing.xl,
              ),
              child: PrimaryButton(
                label: 'Сохранить',
                isBusy: _isSaving,
                onPressed: _hasChanges && !_isSaving ? _save : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.readout,
    required this.child,
  });

  final String label;
  final Widget readout;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: AppText.label),
        const SizedBox(height: AppSpacing.sm),
        readout,
        const SizedBox(height: AppSpacing.sm),
        child,
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
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
            label,
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

class _NotificationToggle extends StatelessWidget {
  const _NotificationToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Row(
        children: [
          const Icon(
            Icons.lock_clock_outlined,
            color: AppColors.accentMid,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Шаги на экране блокировки',
                  style: AppText.title.copyWith(fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  'Постоянное уведомление с кольцом прогресса',
                  style: AppText.body.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.background,
            activeTrackColor: AppColors.accentMid,
            inactiveThumbColor: AppColors.textMuted,
            inactiveTrackColor: AppColors.surfaceRaised,
          ),
        ],
      ),
    );
  }
}

/// Shows what the new measurements mean before they are saved, so the ruler
/// has visible consequences instead of being two numbers on trust.
class _Preview extends StatelessWidget {
  const _Preview({required this.heightCm, required this.weightKg});

  final int heightCm;
  final double weightKg;

  @override
  Widget build(BuildContext context) {
    final kcalPer10k = activeKcal(
      steps: 10000,
      heightCm: heightCm,
      weightKg: weightKg,
      activeMinutes: 100,
    ).round();

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('С ЭТИМИ ДАННЫМИ', style: AppText.label),
          const SizedBox(height: AppSpacing.md),
          _PreviewRow(
            label: 'Длина шага',
            value: '${strideMeters(heightCm).toStringAsFixed(2)} м',
          ),
          const SizedBox(height: AppSpacing.sm),
          _PreviewRow(
            label: '10 000 шагов',
            value: formatDistance(distanceKm(steps: 10000, heightCm: heightCm)),
          ),
          const SizedBox(height: AppSpacing.sm),
          _PreviewRow(label: 'Это примерно', value: '$kcalPer10k ккал'),
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppText.body.copyWith(fontSize: 13)),
        Text(
          value,
          style: AppText.body.copyWith(
            fontSize: 13,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
