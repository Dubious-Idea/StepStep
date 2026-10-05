import 'package:flutter/services.dart';

import '../models/day_stats.dart';
import '../models/profile.dart';
import 'calendar_math.dart';

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

  static const EventChannel _live = EventChannel('com.purrweb.stepstep/live');

  Future<StepSnapshot> snapshot() => _snapshotCall('getSnapshot');

  /// Flushes the hardware counter first, so a freshly opened app shows steps
  /// up to this moment rather than up to the last batch the native counter
  /// happened to receive.
  Future<StepSnapshot> refreshFromSensor() =>
      _snapshotCall('refreshFromSensor');

  /// Fresh snapshots pushed by the native counter while the app is open —
  /// one per batch of steps it folds in, so the ring grows during a walk
  /// instead of only when the app comes back to the foreground.
  Stream<StepSnapshot> liveSnapshots() => _live
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map((event) => StepSnapshot.fromMap(event as Map<dynamic, dynamic>));

  /// `Build.MANUFACTURER`, e.g. to show the HyperOS-only autostart hint.
  /// Empty when the native side is unavailable.
  Future<String> deviceManufacturer() async {
    try {
      return await _channel.invokeMethod<String>('deviceManufacturer') ?? '';
    } on PlatformException {
      return '';
    } on MissingPluginException {
      return '';
    }
  }

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

  /// Marks onboarding complete and starts the native step counter.
  Future<void> startTracking() async {
    try {
      await _channel.invokeMethod<void>('startTracking');
    } on PlatformException {
      // Tracking is best-effort: the UI still works from stored data.
    } on MissingPluginException {
      // Running on a platform without the native side (tests, desktop).
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
