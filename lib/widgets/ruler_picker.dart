import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

/// Horizontal ruler for entering height and weight.
///
/// A ruler rather than a text field because these are physical quantities the
/// user is estimating, not typing exactly — sliding past the tick marks gives
/// a sense of scale that a bare number never does, and it removes keyboard
/// handling and input validation from onboarding entirely.
class RulerPicker extends StatefulWidget {
  const RulerPicker({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
    this.majorEvery = 5,
    this.tickSpacing = 14,
    this.height = 92,
  });

  final double value;
  final double min;
  final double max;
  final double step;

  /// Every n-th tick is drawn tall and labelled.
  final int majorEvery;
  final double tickSpacing;
  final double height;
  final ValueChanged<double> onChanged;

  @override
  State<RulerPicker> createState() => _RulerPickerState();
}

class _RulerPickerState extends State<RulerPicker> {
  late final ScrollController _controller = ScrollController(
    initialScrollOffset: _offsetFor(widget.value),
  );
  late double _reported = widget.value;

  int get _tickCount => ((widget.max - widget.min) / widget.step).round() + 1;

  double _offsetFor(double value) =>
      ((value - widget.min) / widget.step) * widget.tickSpacing;

  double _valueFor(double offset) {
    final index = (offset / widget.tickSpacing).round();
    final value = widget.min + index * widget.step;
    return value.clamp(widget.min, widget.max);
  }

  @override
  void didUpdateWidget(RulerPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only chase externally driven changes; echoing our own scroll back would
    // fight the user's finger.
    if (widget.value != _reported && _controller.hasClients) {
      _reported = widget.value;
      _controller.jumpTo(_offsetFor(widget.value));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification is! ScrollUpdateNotification) return false;

    final value = _valueFor(notification.metrics.pixels);
    if (value == _reported) return false;

    _reported = value;
    HapticFeedback.selectionClick();
    widget.onChanged(value);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sidePadding = constraints.maxWidth / 2;

          return Stack(
            alignment: Alignment.center,
            children: [
              NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: ListView.builder(
                  controller: _controller,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.symmetric(horizontal: sidePadding),
                  itemExtent: widget.tickSpacing,
                  itemCount: _tickCount,
                  itemBuilder: (context, index) => _Tick(
                    value: widget.min + index * widget.step,
                    isMajor: index % widget.majorEvery == 0,
                    height: widget.height,
                  ),
                ),
              ),
              IgnorePointer(child: _CenterMarker(height: widget.height)),
              // Fade the ruler into the background at both edges so it reads
              // as continuous rather than as a clipped list.
              const IgnorePointer(child: _EdgeFade()),
            ],
          );
        },
      ),
    );
  }
}

class _Tick extends StatelessWidget {
  const _Tick({
    required this.value,
    required this.isMajor,
    required this.height,
  });

  final double value;
  final bool isMajor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Container(
          width: isMajor ? 2 : 1,
          height: isMajor ? height * 0.38 : height * 0.20,
          decoration: BoxDecoration(
            color: isMajor ? AppColors.textSecondary : AppColors.stroke,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        if (isMajor) ...[
          const SizedBox(height: AppSpacing.sm),
          // Each tick is only `tickSpacing` wide, which is narrower than the
          // label it carries. OverflowBox lets the text lay out at its natural
          // width and stay centred on its tick, instead of wrapping one
          // character per line inside a 14px slot.
          SizedBox(
            height: 14,
            child: OverflowBox(
              maxWidth: 64,
              child: Text(
                _label(value),
                softWrap: false,
                textAlign: TextAlign.center,
                style: AppText.label.copyWith(fontSize: 10, letterSpacing: 0),
              ),
            ),
          ),
        ],
      ],
    );
  }

  static String _label(double value) =>
      value == value.roundToDouble() ? '${value.round()}' : value.toString();
}

class _CenterMarker extends StatelessWidget {
  const _CenterMarker({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Container(
          width: 3,
          height: height * 0.46,
          decoration: BoxDecoration(
            color: AppColors.accentStart,
            borderRadius: BorderRadius.circular(2),
            boxShadow: const [
              BoxShadow(
                color: AppColors.accentStart,
                blurRadius: 14,
                spreadRadius: -1,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EdgeFade extends StatelessWidget {
  const _EdgeFade();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.background,
            Color(0x0008090C),
            Color(0x0008090C),
            AppColors.background,
          ],
          stops: [0, 0.18, 0.82, 1],
        ),
      ),
      child: SizedBox(width: double.infinity, height: double.infinity),
    );
  }
}

/// Large read-out that sits above the ruler.
class MeasureReadout extends StatelessWidget {
  const MeasureReadout({
    super.key,
    required this.value,
    required this.unit,
    this.fractionDigits = 0,
  });

  final double value;
  final String unit;
  final int fractionDigits;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          value.toStringAsFixed(fractionDigits),
          style: AppText.display.copyWith(fontSize: 72),
        ),
        const SizedBox(width: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Text(
            unit,
            style: AppText.title.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}
