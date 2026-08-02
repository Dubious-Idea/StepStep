import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// GitHub repository releases are published to. Update checks read this repo's
/// latest release and compare its tag against the installed version.
const String kGithubRepo = 'Arti-Ko/StepStep';

/// A release newer than the one installed.
class AvailableUpdate {
  const AvailableUpdate({
    required this.version,
    required this.currentVersion,
    required this.notes,
    required this.downloadUrl,
  });

  final String version;
  final String currentVersion;
  final String notes;

  /// Direct APK asset when the release has one, otherwise the release page.
  final String downloadUrl;
}

/// Outcome of a check, so the caller can tell "up to date" from "could not
/// reach GitHub" — the same silence would otherwise mean both.
sealed class UpdateResult {
  const UpdateResult();
}

final class UpdateAvailable extends UpdateResult {
  const UpdateAvailable(this.update);
  final AvailableUpdate update;
}

final class UpToDate extends UpdateResult {
  const UpToDate(this.currentVersion);
  final String currentVersion;
}

final class UpdateCheckFailed extends UpdateResult {
  const UpdateCheckFailed();
}

/// Checks GitHub Releases for a newer APK.
///
/// The app is distributed outside any store, so this is the only way a user
/// hears about a new build. It reads a public endpoint, sends nothing, and
/// never downloads or installs on its own — tapping through hands the APK URL
/// to the system, which applies its own install prompt.
class UpdateChecker {
  const UpdateChecker();

  static const MethodChannel _channel = MethodChannel(
    'com.purrweb.stepstep/steps',
  );

  static const Duration _timeout = Duration(seconds: 12);

  /// Version of the APK actually installed, read from the package manager.
  Future<String> currentVersion() async {
    try {
      final version = await _channel.invokeMethod<String>('appVersion');
      if (version != null && version.isNotEmpty) return version;
    } on PlatformException {
      // Fall through to the placeholder below.
    } on MissingPluginException {
      // Not running on a platform with the native side.
    }
    return '0.0.0';
  }

  Future<String?> skippedVersion() async {
    try {
      return await _channel.invokeMethod<String>('skippedUpdateVersion');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> skipVersion(String version) async {
    try {
      await _channel.invokeMethod<void>('setSkippedUpdateVersion', {
        'version': version,
      });
    } on PlatformException {
      // Worst case the prompt reappears next launch.
    } on MissingPluginException {
      // Not running on a platform with the native side.
    }
  }

  Future<bool> openUrl(String url) async {
    try {
      return await _channel.invokeMethod<bool>('openUrl', {'url': url}) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<UpdateResult> check() async {
    final current = await currentVersion();
    HttpClient? client;

    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final request = await client.getUrl(
        Uri.parse('https://api.github.com/repos/$kGithubRepo/releases/latest'),
      );
      request.headers.set(HttpHeaders.userAgentHeader, 'StepStep-Android');
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );

      final response = await request.close().timeout(_timeout);
      if (response.statusCode != HttpStatus.ok) {
        return const UpdateCheckFailed();
      }

      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      final tag = (json['tag_name'] as String? ?? '').replaceFirst(
        RegExp(r'^v'),
        '',
      );
      if (tag.isEmpty) return const UpdateCheckFailed();
      if (!isNewer(tag, current)) return UpToDate(current);

      return UpdateAvailable(
        AvailableUpdate(
          version: tag,
          currentVersion: current,
          notes: (json['body'] as String? ?? '').trim(),
          downloadUrl:
              _apkAssetUrl(json) ??
              json['html_url'] as String? ??
              'https://github.com/$kGithubRepo/releases/latest',
        ),
      );
    } on SocketException {
      return const UpdateCheckFailed();
    } on HttpException {
      return const UpdateCheckFailed();
    } on FormatException {
      return const UpdateCheckFailed();
    } finally {
      client?.close(force: true);
    }
  }

  static String? _apkAssetUrl(Map<String, dynamic> release) {
    for (final asset in (release['assets'] as List? ?? const [])) {
      if (asset is! Map) continue;
      final name = (asset['name'] as String? ?? '').toLowerCase();
      if (name.endsWith('.apk')) {
        return asset['browser_download_url'] as String?;
      }
    }
    return null;
  }

  /// True when [remote] is a higher version than [local].
  ///
  /// Compares major/minor/patch numerically — a plain string compare would
  /// call `0.10.0` older than `0.9.0`.
  static bool isNewer(String remote, String local) {
    List<int> parts(String value) => value
        .replaceFirst(RegExp(r'^v'), '')
        .split(RegExp(r'[.+\-]'))
        .map((part) => int.tryParse(part) ?? 0)
        .toList();

    final r = parts(remote);
    final l = parts(local);
    for (var i = 0; i < 3; i++) {
      final a = i < r.length ? r[i] : 0;
      final b = i < l.length ? l[i] : 0;
      if (a != b) return a > b;
    }
    return false;
  }
}
