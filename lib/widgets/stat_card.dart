import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Raised surface used across the app. Depth comes from a real colour step
/// plus a hairline edge, not from a drop shadow that a dark UI would swallow.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.accent,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// When set, tints the top edge — how a card signals which metric it owns.
  final Color? accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.stroke),
        gradient: accent == null
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(
                    accent!.withValues(alpha: 0.10),
                    AppColors.surface,
                  ),
                  AppColors.surface,
                ],
                stops: const [0, 0.65],
              ),
      ),
      child: child,
    );

    if (onTap == null) return card;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        splashColor: (accent ?? AppColors.accentMid).withValues(alpha: 0.10),
        highlightColor: (accent ?? AppColors.accentMid).withValues(alpha: 0.05),
        child: card,
      ),
    );
  }
}

/// One metric: a coloured value, its unit, and a quiet caption.
///
/// [emphasis] drives the type scale so the bento grid has a clear primary —
/// calories are the reason the user entered height and weight, so they get the
/// large treatment and distance gets the small one.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.value,
    required this.unit,
    required this.caption,
    required this.accent,
    required this.icon,
    this.emphasis = StatEmphasis.normal,
    this.footnote,
  });

  final String value;
  final String unit;
  final String caption;
  final Color accent;
  final IconData icon;
  final StatEmphasis emphasis;

  /// Context under the value. Gives the large tile a reason to be tall
  /// instead of leaving a hollow gap between its label and its number.
  final String? footnote;

  bool get _isLarge => emphasis == StatEmphasis.large;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      accent: accent,
      padding: EdgeInsets.all(_isLarge ? AppSpacing.lg : AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: _isLarge ? 18 : 15, color: accent),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  caption.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label.copyWith(fontSize: _isLarge ? 11 : 10),
                ),
              ),
            ],
          ),
          SizedBox(height: _isLarge ? AppSpacing.md : AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.statValue.copyWith(
                        fontSize: _isLarge ? 44 : 22,
                        color: accent,
                        letterSpacing: _isLarge ? -1.6 : -0.4,
                      ),
                    ),
                  ),
                  if (unit.isNotEmpty) ...[
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      unit,
                      style: AppText.body.copyWith(
                        fontSize: _isLarge ? 14 : 12,
                      ),
                    ),
                  ],
                ],
              ),
              if (footnote != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  footnote!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body.copyWith(
                    fontSize: 12,
                    height: 1.35,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

enum StatEmphasis { normal, large }
