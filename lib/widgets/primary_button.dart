import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The app's single call-to-action style: the accent gradient lifted off the
/// graphite background by a coloured glow, so the primary action is impossible
/// to confuse with a surface.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isBusy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null && !isBusy;

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: AnimatedOpacity(
        duration: AppDuration.fast,
        opacity: isEnabled ? 1 : 0.55,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            gradient: const LinearGradient(
              colors: [AppColors.accentStart, AppColors.accentMid],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.accentMid.withValues(alpha: 0.28),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isEnabled ? onPressed : null,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              splashColor: Colors.white24,
              highlightColor: Colors.white10,
              child: Center(
                child: isBusy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.background,
                        ),
                      )
                    : Text(label, style: AppText.button),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
