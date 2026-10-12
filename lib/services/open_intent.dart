import 'dart:io';

import 'package:flutter/services.dart';

/// Receives PDFs opened from other Android apps ("Open with" / "Share").
/// The Android side (MainActivity.kt) copies the file into Folio's storage
/// and passes its path here.
class OpenIntentService {
  static const _channel = MethodChannel('folio/open_file');

  /// The PDF Folio was launched with, if any.
  static Future<String?> initialFile() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('getInitialFile');
    } catch (_) {
      return null;
    }
  }

  /// Called when a PDF is opened while Folio is already running.
  static void listen(void Function(String path) onFile) {
    if (!Platform.isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'fileOpened' && call.arguments is String) {
        onFile(call.arguments as String);
      }
    });
  }
}
