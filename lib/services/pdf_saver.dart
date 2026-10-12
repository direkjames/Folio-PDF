import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:share_plus/share_plus.dart';

/// Saving works differently per platform:
/// - Windows: normal "Save As" dialog and direct file writes.
/// - Android: apps can't write to arbitrary folders, so "Save As" opens the
///   share sheet, where the user picks Files, Drive, a chat app, etc.
class PdfSaver {
  static bool get canChooseSaveLocation => !Platform.isAndroid && !Platform.isIOS;

  /// Writes [bytes] to [path] safely: the full PDF is written to a temp file
  /// first and only then copied over the original, so a failure part-way
  /// through can't leave a half-written PDF in place of the user's file.
  static Future<void> writeTo(String path, Uint8List bytes) async {
    final temp = File('$path.folio-tmp');
    await temp.writeAsBytes(bytes, flush: true);
    try {
      await temp.copy(path); // overwrites the original
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  /// Shows "Save As" (Windows) and writes the file. Returns the new path,
  /// or null if cancelled. On Android this shares the file instead and returns null.
  static Future<String?> saveAs(Uint8List bytes, {required String suggestedName}) async {
    final name = ensurePdfExtension(suggestedName);
    if (!canChooseSaveLocation) {
      await share(bytes, name: name);
      return null;
    }
    final location = await fs.getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: const [
        fs.XTypeGroup(label: 'PDF files', extensions: <String>['pdf']),
      ],
    );
    if (location == null) return null;
    final path = ensurePdfExtension(location.path);
    await writeTo(path, bytes);
    return path;
  }

  /// Opens the system share sheet with the PDF attached.
  static Future<void> share(Uint8List bytes, {required String name}) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, name: ensurePdfExtension(name), mimeType: 'application/pdf')],
      ),
    );
  }

  static String ensurePdfExtension(String name) =>
      name.toLowerCase().endsWith('.pdf') ? name : '$name.pdf';

  /// "report.pdf" -> "report (pages 2-4).pdf"
  static String withSuffix(String name, String suffix) {
    final base = name.toLowerCase().endsWith('.pdf') ? name.substring(0, name.length - 4) : name;
    return '$base ($suffix).pdf';
  }
}
