import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/day_stats.dart';
import '../models/profile.dart';
import '../services/metrics.dart';
import '../services/permissions.dart';
import '../services/step_bridge.dart';
import '../services/update_checker.dart';
import '../theme/tokens.dart';
import '../widgets/primary_button.dart';
import '../widgets/ruler_picker.dart';
import '../widgets/stat_card.dart';
import '../widgets/update_dialog.dart';

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

  late double _heightCm = widget.snapshot.heightCm.toDouble();
  late double _weightKg = widget.snapshot.weightKg;
  late int _goal = widget.snapshot.goal;
  late final TextEditingController _goalController = TextEditingController(
    text: '$_goal',
  );

  bool _liveNotification = true;
  bool _isSaving = false;
  bool _goalValid = true;
  bool _isCheckingUpdate = false;
  bool _autoUpdateCheckEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadNotificationSetting();
    _loadAutoUpdateCheckSetting();
  }

  @override
  void dispose() {
    _goalController.dispose();
    super.dispose();
  }

  void _onGoalChanged(String text) {
    final parsed = int.tryParse(text);
    setState(() {
      _goalValid =
          parsed != null &&
          parsed >= Profile.minGoal &&
          parsed <= Profile.maxGoal;
      if (parsed != null) _goal = parsed;
    });
  }

  Future<void> _loadNotificationSetting() async {
    final enabled = await _bridge.isLiveNotificationEnabled();
    if (mounted) setState(() => _liveNotification = enabled);
  }

  Future<void> _loadAutoUpdateCheckSetting() async {
    const checker = UpdateChecker();
    final enabled = await checker.isAutoCheckEnabled();
    if (mounted) setState(() => _autoUpdateCheckEnabled = enabled);
  }

  Future<void> _toggleAutoUpdateCheck(bool enabled) async {
    setState(() => _autoUpdateCheckEnabled = enabled);
    const checker = UpdateChecker();
    await checker.setAutoCheckEnabled(enabled);
  }

  bool get _hasChanges =>
      _goalValid &&
      (_heightCm.round() != widget.snapshot.heightCm ||
          _weightKg != widget.snapshot.weightKg ||
          _goal != widget.snapshot.goal);

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

  /// Manual counterpart to the silent auto-check on the home screen — this
  /// one always tells the user something, including "up to date" and
  /// "couldn't reach GitHub", which the auto-check deliberately swallows.
  Future<void> _checkForUpdates() async {
    setState(() => _isCheckingUpdate = true);
    const checker = UpdateChecker();
    final result = await checker.check();
    if (!mounted) return;
    setState(() => _isCheckingUpdate = false);

    if (result is UpdateAvailable) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => UpdateDialog(
          update: result.update,
          onInstall: () {
            Navigator.of(dialogContext).pop();
            checker.openUrl(result.update.downloadUrl);
          },
          onSkip: () {
            Navigator.of(dialogContext).pop();
            checker.skipVersion(result.update.version);
          },
        ),
      );
    } else if (result is UpToDate) {
      _showMessage('У вас последняя версия');
    } else {
      _showMessage('Не удалось проверить обновления');
    }
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
                  _GoalInput(
                    controller: _goalController,
                    isValid: _goalValid,
                    onChanged: _onGoalChanged,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _NotificationToggle(
                    value: _liveNotification,
                    onChanged: _toggleNotification,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _AutoUpdateCheckToggle(
                    value: _autoUpdateCheckEnabled,
                    onChanged: _toggleAutoUpdateCheck,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _UpdateCheckRow(
                    isChecking: _isCheckingUpdate,
                    onTap: _isCheckingUpdate ? null : _checkForUpdates,
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

/// Freeform replacement for the old goal presets: a plain number field rather
/// than a fixed set of chips, so any target in range is a direct edit away
/// instead of a guess at the nearest preset.
class _GoalInput extends StatelessWidget {
  const _GoalInput({
    required this.controller,
    required this.isValid,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool isValid;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SurfaceCard(
          child: Row(
            children: [
              const Icon(
                Icons.flag_outlined,
                color: AppColors.accentMid,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(5),
                  ],
                  style: AppText.statValue.copyWith(fontSize: 22),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                  ),
                ),
              ),
              Text('шагов', style: AppText.body.copyWith(fontSize: 13)),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          isValid
              ? 'От ${formatSteps(Profile.minGoal)} до ${formatSteps(Profile.maxGoal)}'
              : 'Введите число от ${formatSteps(Profile.minGoal)} '
                    'до ${formatSteps(Profile.maxGoal)}',
          style: AppText.body.copyWith(
            fontSize: 12,
            color: isValid ? AppColors.textMuted : AppColors.calories,
          ),
        ),
      ],
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

class _AutoUpdateCheckToggle extends StatelessWidget {
  const _AutoUpdateCheckToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Row(
        children: [
          const Icon(
            Icons.event_repeat_rounded,
            color: AppColors.accentMid,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Автопроверка обновлений',
                  style: AppText.title.copyWith(fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  'Раз в сутки при запуске приложения',
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

/// Manual, explicit counterpart to the silent auto-check on the home screen.
class _UpdateCheckRow extends StatelessWidget {
  const _UpdateCheckRow({required this.isChecking, required this.onTap});

  final bool isChecking;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      onTap: onTap,
      child: Row(
        children: [
          const Icon(
            Icons.system_update_alt_rounded,
            color: AppColors.accentMid,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Проверить обновления',
              style: AppText.title.copyWith(fontSize: 15),
            ),
          ),
          if (isChecking)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.accentMid,
              ),
            )
          else
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: AppColors.textMuted,
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
