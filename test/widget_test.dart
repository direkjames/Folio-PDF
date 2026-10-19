import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio_pdf/screens/home_screen.dart';
import 'package:folio_pdf/screens/settings_screen.dart';
import 'package:folio_pdf/services/file_opener.dart';
import 'package:folio_pdf/services/recent_files.dart';
import 'package:folio_pdf/services/settings.dart';
import 'package:folio_pdf/theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('fileNameOf handles Windows and Android paths', () {
    expect(fileNameOf(r'C:\Users\me\Documents\report.pdf'), 'report.pdf');
    expect(fileNameOf('/data/user/0/cache/report.pdf'), 'report.pdf');
  });

  group('SettingsStore', () {
    test('defaults to system theme and normal pages', () async {
      SharedPreferences.setMockInitialValues({});
      await SettingsStore.instance.load();
      expect(SettingsStore.instance.themeMode, ThemeMode.system);
      expect(SettingsStore.instance.readingMode, ReadingMode.normal);
    });

    test('migrates the old dark pages switch', () async {
      SharedPreferences.setMockInitialValues({'dark_reading': true});
      await SettingsStore.instance.load();
      expect(SettingsStore.instance.readingMode, ReadingMode.dark);
    });

    test('remembers choices', () async {
      SharedPreferences.setMockInitialValues({});
      await SettingsStore.instance.load();
      await SettingsStore.instance.setThemeMode(ThemeMode.light);
      await SettingsStore.instance.setReadingMode(ReadingMode.sepia);
      await SettingsStore.instance.load();
      expect(SettingsStore.instance.themeMode, ThemeMode.light);
      expect(SettingsStore.instance.readingMode, ReadingMode.sepia);
    });
  });

  group('RecentFilesStore', () {
    test('flags files that no longer exist, without touching the disk on read', () async {
      final dir = await Directory.systemTemp.createTemp('folio_test');
      addTearDown(() => dir.delete(recursive: true));
      final real = File('${dir.path}/real.pdf')..writeAsBytesSync([1]);
      SharedPreferences.setMockInitialValues({});
      final store = RecentFilesStore.instance;
      await store.clear();
      await store.touch(real.path, 'real.pdf');
      await store.touch('${dir.path}/gone.pdf', 'gone.pdf');
      await store.refreshAvailability();
      expect(store.isMissing(real.path), isFalse);
      expect(store.isMissing('${dir.path}/gone.pdf'), isTrue);
      await store.clear();
    });

    test('keeps the reading position in memory and writes it on flush', () async {
      SharedPreferences.setMockInitialValues({});
      final store = RecentFilesStore.instance;
      await store.clear();
      await store.touch('/tmp/a.pdf', 'a.pdf');
      await store.updateProgress('/tmp/a.pdf', lastPage: 7, pageCount: 20);
      expect(store.find('/tmp/a.pdf')?.lastPage, 7);
      await store.flush();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('recent_files_v1'), contains('"lastPage":7'));
      await store.clear();
    });
  });

  group('screens', () {
    Widget app(Widget home, Brightness b) => MaterialApp(theme: buildAppTheme(b), home: home);

    testWidgets('home shows the empty library in dark and light', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await RecentFilesStore.instance.clear();
      for (final b in Brightness.values) {
        await tester.pumpWidget(app(const HomeScreen(), b));
        await tester.pump();
        expect(find.text('Open a PDF'), findsOneWidget);
        expect(find.text('Your library is empty'), findsOneWidget);
      }
    });

    testWidgets('settings lets you pick a theme', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsStore.instance.load();
      await tester.pumpWidget(app(const SettingsScreen(), Brightness.dark));
      await tester.tap(find.text('Light'));
      await tester.pump();
      expect(SettingsStore.instance.themeMode, ThemeMode.light);
    });
  });
}
