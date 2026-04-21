// lib/app_version.dart

import 'package:package_info_plus/package_info_plus.dart';

class AppVersion {
  static PackageInfo? _info;

  static Future<void> init() async {
    _info ??= await PackageInfo.fromPlatform();
  }

  /// e.g. "1.2.0+45"
  static String get label {
    final i = _info;
    if (i == null) return '';
    return '${i.version}+${i.buildNumber}';
  }
}