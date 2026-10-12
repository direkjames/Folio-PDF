import 'package:file_selector/file_selector.dart' as fs;

/// Shows the system file picker filtered to PDFs.
/// Returns the chosen file's path and display name, or null if cancelled.
Future<({String path, String name})?> pickPdf() async {
  const pdfGroup = fs.XTypeGroup(
    label: 'PDF files',
    extensions: <String>['pdf'],
    mimeTypes: <String>['application/pdf'],
    uniformTypeIdentifiers: <String>['com.adobe.pdf'],
  );
  final file = await fs.openFile(acceptedTypeGroups: const [pdfGroup]);
  if (file == null) return null;
  return (path: file.path, name: file.name.isNotEmpty ? file.name : fileNameOf(file.path));
}

String fileNameOf(String path) {
  final parts = path.split(RegExp(r'[\\/]'));
  return parts.isEmpty ? path : parts.last;
}
