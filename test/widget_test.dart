import 'package:flutter_test/flutter_test.dart';
import 'package:folio_pdf/services/file_opener.dart';

void main() {
  test('fileNameOf handles Windows and Android paths', () {
    expect(fileNameOf(r'C:\Users\me\Documents\report.pdf'), 'report.pdf');
    expect(fileNameOf('/data/user/0/cache/report.pdf'), 'report.pdf');
  });
}
