import 'package:flutter/services.dart';

/// Outcome of asking for the two permissions the counter needs.
///
/// They are not equal: without activity recognition nothing can be counted at
/// all, while without notifications the app still works and only loses its
/// lock-screen presence. The UI treats them differently, so the result keeps
/// them apart instead of collapsing to a single bool.
class PermissionOutcome {
  const PermissionOutcome({
    required this.canCountSteps,
    required this.canShowNotification,
    required this.isPermanentlyDenied,
  });

  const PermissionOutcome.denied()
    : canCountSteps = false,
      canShowNotification = false,
      isPermanentlyDenied = false;

  final bool canCountSteps;
  final bool canShowNotification;

  /// The user chose "don't ask again" — only Settings can undo it.
  final bool isPermanentlyDenied;

  factory PermissionOutcome.fromMap(Map<dynamic, dynamic> map) =>
      PermissionOutcome(
        canCountSteps: map['canCountSteps'] as bool? ?? false,
        canShowNotification: map['canShowNotification'] as bool? ?? false,
        isPermanentlyDenied: map['isPermanentlyDenied'] as bool? ?? false,
      );
}

/// Permission prompts, handled by the same native activity that owns the
/// sensor — no plugin, so nothing pins the build to a given compileSdk.
class StepPermissions {
  const StepPermissions();

  static const MethodChannel _channel = MethodChannel(
    'com.purrweb.stepstep/steps',
  );

  /// Prompts for whatever is still missing. Resolves once the system dialogs
  /// have been dismissed; resolves immediately if nothing is missing.
  Future<PermissionOutcome> request() => _outcomeCall('requestPermissions');

  Future<PermissionOutcome> status() => _outcomeCall('permissionStatus');

  Future<void> openSettings() async {
    try {
      await _channel.invokeMethod<void>('openAppSettings');
    } on PlatformException {
      // Nothing else to offer if the settings screen will not open.
    } on MissingPluginException {
      // Not running on a platform with the native side.
    }
  }

  Future<PermissionOutcome> _outcomeCall(String method) async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(method);
      if (raw == null) return const PermissionOutcome.denied();
      return PermissionOutcome.fromMap(raw);
    } on PlatformException {
      return const PermissionOutcome.denied();
    } on MissingPluginException {
      return const PermissionOutcome.denied();
    }
  }
}
