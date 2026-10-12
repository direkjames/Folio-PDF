import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import '../services/file_opener.dart';
import '../services/pdf_saver.dart';
import '../theme.dart';
import '../widgets/password_dialog.dart';

/// What the organize screen hands back to the viewer when the user taps Done.
class OrganizeResult {
  const OrganizeResult({required this.bytes, required this.pageCount});
  final Uint8List bytes;
  final int pageCount;
}

/// One page in the working list. Pages can come from the current PDF or from
/// PDFs the user adds (merge), and carry their own rotation.
class _PageItem {
  _PageItem({
    required this.uid,
    required this.doc,
    required this.pageNumber,
    required this.rotation,
    required this.sourceName,
    required this.fromOtherFile,
  });

  final int uid;
  final PdfDocument doc;
  final int pageNumber; // 1-based, inside [doc]
  final PdfPageRotation rotation;
  final String sourceName;
  final bool fromOtherFile;

  PdfPage get page => doc.pages[pageNumber - 1];

  /// The page as it should be written to the output, with rotation applied.
  PdfPage get outputPage => rotation == page.rotation ? page : page.rotatedTo(rotation);

  _PageItem rotated({required bool clockwise}) => _PageItem(
        uid: uid,
        doc: doc,
        pageNumber: pageNumber,
        rotation: clockwise ? rotation.rotateCW90 : rotation.rotateCCW90,
        sourceName: sourceName,
        fromOtherFile: fromOtherFile,
      );
}

/// Reorder, rotate, delete, extract and merge pages.
class OrganizeScreen extends StatefulWidget {
  const OrganizeScreen({
    required this.bytes,
    required this.fileName,
    this.password,
    super.key,
  });

  final Uint8List bytes;
  final String fileName;
  final String? password;

  @override
  State<OrganizeScreen> createState() => _OrganizeScreenState();
}

class _OrganizeScreenState extends State<OrganizeScreen> {
  PdfDocument? _baseDoc;
  final _otherDocs = <PdfDocument>[];
  List<_PageItem> _items = [];
  final _history = <List<_PageItem>>[];
  final _selected = <int>{}; // uids
  int _nextUid = 0;
  bool _busy = false;
  String? _loadError;

  bool get _hasChanges => _history.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseDoc?.dispose();
    for (final d in _otherDocs) {
      d.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final doc = await PdfDocument.openData(
        widget.bytes,
        sourceName: 'organize:${widget.fileName}:${DateTime.now().microsecondsSinceEpoch}',
        passwordProvider: () => widget.password,
      );
      if (!mounted) {
        doc.dispose();
        return;
      }
      setState(() {
        _baseDoc = doc;
        _items = _itemsFor(doc, widget.fileName, fromOtherFile: false);
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = e.toString());
    }
  }

  List<_PageItem> _itemsFor(PdfDocument doc, String name, {required bool fromOtherFile}) => [
        for (var i = 0; i < doc.pages.length; i++)
          _PageItem(
            uid: _nextUid++,
            doc: doc,
            pageNumber: i + 1,
            rotation: doc.pages[i].rotation,
            sourceName: name,
            fromOtherFile: fromOtherFile,
          ),
      ];

  /// Records the current state so it can be undone, then applies [change].
  void _edit(void Function() change) {
    _history.add(List.of(_items));
    if (_history.length > 50) _history.removeAt(0);
    setState(change);
  }

  void _undo() {
    if (_history.isEmpty) return;
    setState(() {
      _items = _history.removeLast();
      _selected.removeWhere((uid) => !_items.any((p) => p.uid == uid));
    });
  }

  void _rotate(Set<int> uids, {required bool clockwise}) {
    if (uids.isEmpty) return;
    _edit(() {
      _items = [for (final p in _items) uids.contains(p.uid) ? p.rotated(clockwise: clockwise) : p];
    });
  }

  void _delete(Set<int> uids) {
    if (uids.isEmpty) return;
    if (uids.length >= _items.length) {
      _snack('A PDF needs at least one page.');
      return;
    }
    _edit(() {
      _items = _items.where((p) => !uids.contains(p.uid)).toList();
      _selected.removeAll(uids);
    });
  }

  void _duplicate(_PageItem item) {
    final i = _items.indexWhere((p) => p.uid == item.uid);
    _edit(() {
      _items.insert(
        i + 1,
        _PageItem(
          uid: _nextUid++,
          doc: item.doc,
          pageNumber: item.pageNumber,
          rotation: item.rotation,
          sourceName: item.sourceName,
          fromOtherFile: item.fromOtherFile,
        ),
      );
    });
  }

  void _reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex == oldIndex) return;
    _edit(() {
      final item = _items.removeAt(oldIndex);
      _items.insert(newIndex, item);
    });
  }

  void _toggleSelect(int uid) {
    setState(() {
      if (!_selected.remove(uid)) _selected.add(uid);
    });
  }

  void _selectAll() => setState(() {
        if (_selected.length == _items.length) {
          _selected.clear();
        } else {
          _selected
            ..clear()
            ..addAll(_items.map((p) => p.uid));
        }
      });

  /// Merge: append all pages of one or more other PDFs.
  Future<void> _addPdfs() async {
    final files = await fs.openFiles(
      acceptedTypeGroups: const [
        fs.XTypeGroup(
          label: 'PDF files',
          extensions: <String>['pdf'],
          mimeTypes: <String>['application/pdf'],
          uniformTypeIdentifiers: <String>['com.adobe.pdf'],
        ),
      ],
    );
    if (files.isEmpty || !mounted) return;
    setState(() => _busy = true);
    final added = <_PageItem>[];
    for (final f in files) {
      final name = f.name.isNotEmpty ? f.name : fileNameOf(f.path);
      try {
        final bytes = await File(f.path).readAsBytes();
        if (!mounted) return;
        final doc = await PdfDocument.openData(
          bytes,
          sourceName: 'merge:$name:${DateTime.now().microsecondsSinceEpoch}',
          passwordProvider: () => showPasswordDialog(context),
        );
        _otherDocs.add(doc);
        added.addAll(_itemsFor(doc, name, fromOtherFile: true));
      } catch (e) {
        _snack('Could not add "$name".');
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (added.isNotEmpty) {
      _edit(() => _items.addAll(added));
      _snack('Added ${added.length} page${added.length == 1 ? '' : 's'}.');
    }
  }

  /// Split: save the selected pages as a new, separate PDF.
  Future<void> _extractSelected() async {
    final pages = _items.where((p) => _selected.contains(p.uid)).toList();
    if (pages.isEmpty) return;
    setState(() => _busy = true);
    try {
      final out = await PdfDocument.createNew(sourceName: 'extract:${DateTime.now().microsecondsSinceEpoch}');
      out.pages = pages.map((p) => p.outputPage).toList();
      final bytes = await out.encodePdf();
      out.dispose();
      final positions = [for (var i = 0; i < _items.length; i++) if (_selected.contains(_items[i].uid)) i + 1];
      final saved = await PdfSaver.saveAs(
        bytes,
        suggestedName: PdfSaver.withSuffix(widget.fileName, 'pages ${_describeRange(positions)}'),
      );
      if (saved != null) _snack('Saved ${pages.length} page${pages.length == 1 ? '' : 's'} to ${fileNameOf(saved)}.');
    } catch (e) {
      _snack('Could not extract pages: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// "1,2,3,5,7,8" -> "1-3, 5, 7-8"
  static String _describeRange(List<int> nums) {
    final parts = <String>[];
    var i = 0;
    while (i < nums.length) {
      var j = i;
      while (j + 1 < nums.length && nums[j + 1] == nums[j] + 1) {
        j++;
      }
      parts.add(i == j ? '${nums[i]}' : '${nums[i]}-${nums[j]}');
      i = j + 1;
    }
    final s = parts.join(', ');
    return s.length > 40 ? '${nums.length} pages' : s;
  }

  Future<void> _done() async {
    final base = _baseDoc;
    if (base == null) return;
    if (!_hasChanges) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _busy = true);
    try {
      final Uint8List bytes;
      if (_onlyRotationsChanged(base)) {
        // Same pages in the same order: edit the original document in place,
        // which keeps its bookmarks, form fields and other document-level data.
        base.pages = _items.map((p) => p.outputPage).toList();
        bytes = await base.encodePdf();
      } else {
        // Pages were moved, deleted, duplicated or added. pdfrx 2.6.5 doesn't
        // apply reordering/deletion when assembling a document in place, so
        // build a fresh PDF and import every page into it (this path works).
        final out = await PdfDocument.createNew(sourceName: 'organized:${DateTime.now().microsecondsSinceEpoch}');
        try {
          out.pages = _items.map((p) => p.outputPage).toList();
          bytes = await out.encodePdf();
        } finally {
          out.dispose();
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop(OrganizeResult(bytes: bytes, pageCount: _items.length));
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      _snack('Could not apply changes: $e');
    }
  }

  /// True when every original page is still there, once, in its original position.
  bool _onlyRotationsChanged(PdfDocument base) {
    if (_items.length != base.pages.length) return false;
    for (var i = 0; i < _items.length; i++) {
      final p = _items[i];
      if (p.fromOtherFile || !identical(p.doc, base) || p.pageNumber != i + 1) return false;
    }
    return true;
  }

  Future<bool> _confirmDiscard() async {
    if (!_hasChanges) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard page changes?'),
        content: const Text('Your reordering, rotations and deletions will be lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep editing')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard')),
        ],
      ),
    );
    return discard ?? false;
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          _history.clear();
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Organize pages'),
          actions: [
            IconButton(
              tooltip: 'Undo',
              onPressed: _history.isEmpty || _busy ? null : _undo,
              icon: const Icon(Icons.undo_rounded),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12, left: 4),
              child: FilledButton(
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10)),
                onPressed: _baseDoc == null || _busy ? null : _done,
                child: const Text('Done'),
              ),
            ),
          ],
          bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider()),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loadError != null) {
      return Center(child: Text('Could not open pages.\n$_loadError', textAlign: TextAlign.center));
    }
    if (_baseDoc == null) return const Center(child: CircularProgressIndicator());

    return Column(
      children: [
        _buildToolbar(),
        if (_busy) const LinearProgressIndicator(minHeight: 2) else const SizedBox(height: 2),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                itemCount: _items.length,
                onReorder: _reorder,
                itemBuilder: (context, index) => _buildRow(index),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    final n = _selected.length;
    final hasSel = n > 0;
    return Material(
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            TextButton.icon(
              onPressed: _busy ? null : _selectAll,
              icon: Icon(
                _selected.length == _items.length ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                size: 20,
              ),
              label: Text(hasSel ? '$n selected' : 'Select all'),
            ),
            const Spacer(),
            if (hasSel) ...[
              IconButton(
                tooltip: 'Rotate left',
                onPressed: _busy ? null : () => _rotate(Set.of(_selected), clockwise: false),
                icon: const Icon(Icons.rotate_left_rounded),
              ),
              IconButton(
                tooltip: 'Rotate right',
                onPressed: _busy ? null : () => _rotate(Set.of(_selected), clockwise: true),
                icon: const Icon(Icons.rotate_right_rounded),
              ),
              IconButton(
                tooltip: 'Delete',
                onPressed: _busy ? null : () => _delete(Set.of(_selected)),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
              IconButton(
                tooltip: PdfSaver.canChooseSaveLocation ? 'Save selected as new PDF' : 'Share selected as new PDF',
                onPressed: _busy ? null : _extractSelected,
                icon: const Icon(Icons.call_split_rounded),
              ),
            ] else
              TextButton.icon(
                onPressed: _busy ? null : _addPdfs,
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Add PDF'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(int index) {
    final item = _items[index];
    final selected = _selected.contains(item.uid);
    final rotatedBy = (item.rotation.index - item.page.rotation.index + 4) % 4 * 90;
    final details = [
      if (item.fromOtherFile) 'from ${item.sourceName} · p.${item.pageNumber}' else 'original p.${item.pageNumber}',
      if (rotatedBy != 0) 'rotated $rotatedBy°',
    ].join(' · ');

    return Padding(
      key: ValueKey(item.uid),
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: selected ? AppColors.accent.withValues(alpha: 0.10) : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? AppColors.accent : AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _toggleSelect(item.uid),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
            child: Row(
              children: [
                Checkbox(value: selected, onChanged: (_) => _toggleSelect(item.uid)),
                SizedBox(
                  width: 64,
                  height: 84,
                  child: PdfPageView(
                    key: ValueKey('org_${item.uid}_${item.rotation.index}'),
                    document: item.doc,
                    pageNumber: item.pageNumber,
                    rotationOverride: item.rotation,
                    maximumDpi: 48,
                    alignment: Alignment.center,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Page ${index + 1}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        details,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: item.fromOtherFile ? AppColors.accent : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Rotate right',
                  onPressed: _busy ? null : () => _rotate({item.uid}, clockwise: true),
                  icon: const Icon(Icons.rotate_right_rounded, size: 20),
                ),
                PopupMenuButton<String>(
                  tooltip: 'More',
                  enabled: !_busy,
                  onSelected: (v) {
                    switch (v) {
                      case 'left':
                        _rotate({item.uid}, clockwise: false);
                      case 'dup':
                        _duplicate(item);
                      case 'delete':
                        _delete({item.uid});
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'left', child: Text('Rotate left')),
                    PopupMenuItem(value: 'dup', child: Text('Duplicate')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    child: Icon(Icons.drag_indicator_rounded, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
