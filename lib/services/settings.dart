import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

/// How PDF pages are tinted on screen. Never changes the file itself.
enum ReadingMode { normal, sepia, dark }

/// App-wide preferences, remembered between sessions.
class SettingsStore extends ChangeNotifier {
  SettingsStore._();
  static final instance = SettingsStore._();

  static const _themeKey = 'theme_mode';
  static const _readingKey = 'reading_mode';
  static const _legacyDarkKey = 'dark_reading'; // before reading modes existed

  ThemeMode _themeMode = ThemeMode.system;
  ReadingMode _readingMode = ReadingMode.normal;

  ThemeMode get themeMode => _themeMode;
  ReadingMode get readingMode => _readingMode;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _themeMode = ThemeMode.values.asNameMap()[prefs.getString(_themeKey)] ?? ThemeMode.system;
      final saved = ReadingMode.values.asNameMap()[prefs.getString(_readingKey)];
      _readingMode = saved ?? ((prefs.getBool(_legacyDarkKey) ?? false) ? ReadingMode.dark : ReadingMode.normal);
    } catch (_) {
      // Unreadable preferences: keep the defaults.
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    await _write((p) => p.setString(_themeKey, mode.name));
  }

  Future<void> setReadingMode(ReadingMode mode) async {
    if (mode == _readingMode) return;
    _readingMode = mode;
    notifyListeners();
    await _write((p) => p.setString(_readingKey, mode.name));
  }

  Future<void> _write(Future<bool> Function(SharedPreferences) op) async {
    try {
      await op(await SharedPreferences.getInstance());
    } catch (_) {
      // Not being able to remember a preference should never break the app.
    }
  }
}
