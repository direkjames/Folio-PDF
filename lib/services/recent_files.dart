import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One entry in the recent files list.
class RecentFile {
  RecentFile({
    required this.path,
    required this.name,
    required this.lastOpened,
    this.lastPage = 1,
    this.pageCount,
  });

  final String path;
  final String name;
  final DateTime lastOpened;

  /// Page the user was on when they closed the file, so it reopens there.
  final int lastPage;
  final int? pageCount;

  bool get exists => File(path).existsSync();

  RecentFile copyWith({DateTime? lastOpened, int? lastPage, int? pageCount}) => RecentFile(
        path: path,
        name: name,
        lastOpened: lastOpened ?? this.lastOpened,
        lastPage: lastPage ?? this.lastPage,
        pageCount: pageCount ?? this.pageCount,
      );

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'lastOpened': lastOpened.toIso8601String(),
        'lastPage': lastPage,
        'pageCount': pageCount,
      };

  static RecentFile? fromJson(Map<String, dynamic> json) {
    try {
      return RecentFile(
        path: json['path'] as String,
        name: json['name'] as String,
        lastOpened: DateTime.parse(json['lastOpened'] as String),
        lastPage: (json['lastPage'] as int?) ?? 1,
        pageCount: json['pageCount'] as int?,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Keeps the recent files list in local storage. Newest first.
class RecentFilesStore extends ChangeNotifier {
  RecentFilesStore._();
  static final instance = RecentFilesStore._();

  static const _key = 'recent_files_v1';
  static const maxEntries = 30;

  List<RecentFile> _files = [];
  List<RecentFile> get files => List.unmodifiable(_files);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      _files = list
          .whereType<Map<String, dynamic>>()
          .map(RecentFile.fromJson)
          .whereType<RecentFile>()
          .toList();
    } catch (_) {
      _files = [];
    }
    notifyListeners();
  }

  RecentFile? find(String path) {
    for (final f in _files) {
      if (f.path == path) return f;
    }
    return null;
  }

  /// Adds the file to the top of the list (or moves it there).
  Future<void> touch(String path, String name) async {
    final existing = find(path);
    _files.removeWhere((f) => f.path == path);
    _files.insert(
      0,
      existing?.copyWith(lastOpened: DateTime.now()) ??
          RecentFile(path: path, name: name, lastOpened: DateTime.now()),
    );
    if (_files.length > maxEntries) _files = _files.sublist(0, maxEntries);
    await _save();
  }

  /// Remembers reading position without reordering the list.
  Future<void> updateProgress(String path, {int? lastPage, int? pageCount}) async {
    final i = _files.indexWhere((f) => f.path == path);
    if (i < 0) return;
    _files[i] = _files[i].copyWith(lastPage: lastPage, pageCount: pageCount);
    await _save();
  }

  Future<void> remove(String path) async {
    _files.removeWhere((f) => f.path == path);
    await _save();
  }

  Future<void> clear() async {
    _files = [];
    await _save();
  }

  Future<void> _save() async {
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_files.map((f) => f.toJson()).toList()));
  }
}
