import 'package:flutter/services.dart';

import '../models/day_stats.dart';
import '../models/profile.dart';
import 'calendar_math.dart';

/// Floor `PeriodicWorkRequest` itself enforces natively — the UI clamps to
/// this rather than letting the user pick something the platform will
/// silently round up anyway.
const int kMinRefreshIntervalMinutes = 15;
const int kMaxRefreshIntervalMinutes = 24 * 60;
const int kDefaultRefreshIntervalMinutes = 30;

/// Typed client for the native step store (`MainActivity` on Android).
///
/// Every call can fail if the platform side is unavailable, so each one
/// degrades to a sensible value instead of throwing into the widget tree —
/// a step counter that shows zero is recoverable, one that crashes is not.
class StepBridge {
  const StepBridge();

  static const MethodChannel _channel = MethodChannel(
    'com.purrweb.stepstep/steps',
  );

  Future<StepSnapshot> snapshot() => _snapshotCall('getSnapshot');

  /// Reads the hardware counter directly, so a freshly opened app already
  /// includes steps taken since the last scheduled background read.
  Future<StepSnapshot> refreshFromSensor() =>
      _snapshotCall('refreshFromSensor');

  Future<StepSnapshot> saveProfile(Profile profile) =>
      _snapshotCall('saveProfile', <String, dynamic>{
        'heightCm': profile.heightCm,
        'weightKg': profile.weightKg,
        'goal': profile.goal,
      });

  Future<List<DayEntry>> history({int days = 7}) async {
    try {
      final raw = await _channel.invokeListMethod<dynamic>('getHistory', {
        'days': days,
      });
      if (raw == null) return const [];
      return raw
          .whereType<Map<dynamic, dynamic>>()
          .map(DayEntry.fromMap)
          .toList(growable: false);
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Steps for every day from [start] to [end], inclusive — unlike [history],
  /// not anchored to today. Backs the month/year browser.
  Future<List<DayEntry>> historyRange({
    required DateTime start,
    required DateTime end,
  }) async {
    try {
      final raw = await _channel.invokeListMethod<dynamic>('getHistoryRange', {
        'start': dayKeyOf(start),
        'end': dayKeyOf(end),
      });
      if (raw == null) return const [];
      return raw
          .whereType<Map<dynamic, dynamic>>()
          .map(DayEntry.fromMap)
          .toList(growable: false);
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  Future<bool> isOnboarded() => _boolCall('isOnboarded', orElse: false);

  Future<bool> hasStepSensor() => _boolCall('hasStepSensor', orElse: false);

  Future<bool> isLiveNotificationEnabled() =>
      _boolCall('isLiveNotificationEnabled', orElse: true);

  Future<bool> setLiveNotificationEnabled(bool enabled) => _boolCall(
    'setLiveNotificationEnabled',
    arguments: {'enabled': enabled},
    orElse: enabled,
  );

  /// Marks onboarding complete and arms the background refresh schedule.
  Future<void> startTracking() async {
    try {
      await _channel.invokeMethod<void>('startTracking');
    } on PlatformException {
      // Tracking is best-effort: the UI still works from stored data.
    } on MissingPluginException {
      // Running on a platform without the native side (tests, desktop).
    }
  }

  /// How often the background schedule wakes the app to read the sensor and
  /// repaint the notification/widgets — see `RefreshScheduler` natively.
  Future<int> refreshIntervalMinutes() async {
    try {
      return await _channel.invokeMethod<int>('refreshIntervalMinutes') ??
          kDefaultRefreshIntervalMinutes;
    } on PlatformException {
      return kDefaultRefreshIntervalMinutes;
    } on MissingPluginException {
      return kDefaultRefreshIntervalMinutes;
    }
  }

  /// @return the interval actually stored, clamped natively to the platform
  ///   floor — the caller should reflect this back rather than assume [minutes]
  ///   stuck verbatim.
  Future<int> setRefreshIntervalMinutes(int minutes) async {
    try {
      return await _channel.invokeMethod<int>('setRefreshIntervalMinutes', {
            'minutes': minutes,
          }) ??
          minutes;
    } on PlatformException {
      return minutes;
    } on MissingPluginException {
      return minutes;
    }
  }

  Future<StepSnapshot> _snapshotCall(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        method,
        arguments,
      );
      if (raw == null) return const StepSnapshot.empty();
      return StepSnapshot.fromMap(raw);
    } on PlatformException {
      return const StepSnapshot.empty();
    } on MissingPluginException {
      return const StepSnapshot.empty();
    }
  }

  Future<bool> _boolCall(
    String method, {
    Map<String, dynamic>? arguments,
    required bool orElse,
  }) async {
    try {
      return await _channel.invokeMethod<bool>(method, arguments) ?? orElse;
    } on PlatformException {
      return orElse;
    } on MissingPluginException {
      return orElse;
    }
  }
}
