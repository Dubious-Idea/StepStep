import 'package:flutter_test/flutter_test.dart';
import 'package:stepstep/services/update_checker.dart';

void main() {
  group('UpdateChecker.isNewer', () {
    test('detects a higher patch, minor and major', () {
      expect(UpdateChecker.isNewer('1.0.1', '1.0.0'), isTrue);
      expect(UpdateChecker.isNewer('1.1.0', '1.0.9'), isTrue);
      expect(UpdateChecker.isNewer('2.0.0', '1.9.9'), isTrue);
    });

    test('compares numerically, not as strings', () {
      // The classic release bug: "0.10.0" sorts before "0.9.0" as text, so a
      // string compare would hide every update after the ninth minor.
      expect(UpdateChecker.isNewer('0.10.0', '0.9.0'), isTrue);
      expect(UpdateChecker.isNewer('1.0.10', '1.0.9'), isTrue);
      expect(UpdateChecker.isNewer('0.9.0', '0.10.0'), isFalse);
    });

    test('is false for the same version', () {
      expect(UpdateChecker.isNewer('1.2.3', '1.2.3'), isFalse);
    });

    test('is false for an older release', () {
      expect(UpdateChecker.isNewer('1.0.0', '1.0.1'), isFalse);
    });

    test('tolerates a leading v on either side', () {
      expect(UpdateChecker.isNewer('v1.1.0', '1.0.0'), isTrue);
      expect(UpdateChecker.isNewer('v1.0.0', 'v1.0.0'), isFalse);
    });

    test('ignores the build suffix Flutter appends', () {
      // pubspec versions look like "1.0.0+7"; the build number must not make
      // an identical release look newer.
      expect(UpdateChecker.isNewer('1.0.0', '1.0.0+7'), isFalse);
      expect(UpdateChecker.isNewer('1.0.1', '1.0.0+7'), isTrue);
    });

    test('treats missing components as zero', () {
      expect(UpdateChecker.isNewer('1.1', '1.0.0'), isTrue);
      expect(UpdateChecker.isNewer('1', '1.0.0'), isFalse);
    });

    test('does not crash on a non-numeric tag', () {
      expect(UpdateChecker.isNewer('nightly', '1.0.0'), isFalse);
      expect(UpdateChecker.isNewer('1.0.1', 'unknown'), isTrue);
    });
  });
}
