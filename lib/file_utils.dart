import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class FileUtils {
  static const _channel = MethodChannel('com.fleet_tracking_poc/file_utils');

  /// Resolves a content URI (from FilePicker.getDirectoryPath) into
  /// a list of real absolute file paths, filtered by [extensions].
  static Future<List<String>> getFilesFromUri(
    String uri, {
    List<String> extensions = const ['mp4', 'mov', 'avi', 'mkv', '3gp', 'webm'],
  }) async {
    debugPrint('FileUtils: uri = $uri');
    final result = await _channel.invokeListMethod<String>('getFilesFromUri', {
      'uri': uri,
      'extensions': extensions,
    });
    debugPrint('FileUtils: result = $result');
    return result ?? [];
  }
}
