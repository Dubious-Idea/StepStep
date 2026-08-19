import 'package:flutter/material.dart';

import '../services/calendar_math.dart';
import '../theme/tokens.dart';
import 'month_screen.dart';

/// Twelve month tiles — tap one to drill into [MonthScreen] and pick a week.
class YearScreen extends StatefulWidget {
  const YearScreen({super.key, required this.initialYear, required this.goal});

  final int initialYear;
  final int goal;

  @override
  State<YearScreen> createState() => _YearScreenState();
}

class _YearScreenState extends State<YearScreen> {
  late int _year = widget.initialYear;

  void _openMonth(int month) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            MonthScreen(year: _year, month: month, goal: widget.goal),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentYear = DateTime.now().year;

    return Scaffold(
      appBar: AppBar(
        title: Text('$_year', style: AppText.title.copyWith(fontSize: 17)),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: 'Предыдущий год',
            onPressed: () => setState(() => _year--),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            tooltip: 'Следующий год',
            onPressed: () => setState(() => _year++),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: AppSpacing.md,
              crossAxisSpacing: AppSpacing.md,
              childAspectRatio: 1.3,
            ),
            itemCount: 12,
            itemBuilder: (context, index) {
              final month = index + 1;
              final isCurrent =
                  _year == currentYear && month == DateTime.now().month;
              return _MonthTile(
                label: monthNamesShort[index],
                isCurrent: isCurrent,
                onTap: () => _openMonth(month),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MonthTile extends StatelessWidget {
  const _MonthTile({
    required this.label,
    required this.isCurrent,
    required this.onTap,
  });

  final String label;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: isCurrent ? AppColors.accentMid : AppColors.stroke,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppText.labelBright.copyWith(
              fontSize: 13,
              letterSpacing: 0.2,
              color: isCurrent ? AppColors.accentMid : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
