import 'package:flutter/services.dart';

import '../models/day_stats.dart';
import '../models/profile.dart';

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
  /// includes steps taken while the service was not running.
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

  Future<bool> isOnboarded() => _boolCall('isOnboarded', orElse: false);

  Future<bool> hasStepSensor() => _boolCall('hasStepSensor', orElse: false);

  Future<bool> isLiveNotificationEnabled() =>
      _boolCall('isLiveNotificationEnabled', orElse: true);

  Future<bool> setLiveNotificationEnabled(bool enabled) => _boolCall(
    'setLiveNotificationEnabled',
    arguments: {'enabled': enabled},
    orElse: enabled,
  );

  /// Marks onboarding complete and brings the live notification up.
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
