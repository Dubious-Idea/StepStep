import 'package:flutter/material.dart';

import '../services/update_checker.dart';
import '../theme/tokens.dart';
import 'primary_button.dart';

/// Offers a newer release. Three ways out on purpose: install now, skip this
/// version for good, or dismiss and be reminded next launch — an update
/// prompt with only "later" comes back forever, and one with only "install"
/// is a wall.
class UpdateDialog extends StatelessWidget {
  const UpdateDialog({
    super.key,
    required this.update,
    required this.onInstall,
    required this.onSkip,
  });

  final AvailableUpdate update;
  final VoidCallback onInstall;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(AppSpacing.xl),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.stroke),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.download_rounded,
                  size: 18,
                  color: AppColors.accentStart,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text('ОБНОВЛЕНИЕ', style: AppText.label),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Версия ${update.version}',
              style: AppText.display.copyWith(fontSize: 30),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Установлена ${update.currentVersion}',
              style: AppText.body.copyWith(fontSize: 13),
            ),
            if (update.notes.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 220),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    update.notes,
                    style: AppText.body.copyWith(fontSize: 13),
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(label: 'Скачать', onPressed: onInstall),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                    ),
                    child: const Text('Позже'),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: onSkip,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textMuted,
                    ),
                    child: const Text('Пропустить'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
