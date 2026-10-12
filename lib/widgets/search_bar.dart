import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import '../theme.dart';

/// Find-in-document bar shown under the app bar.
class PdfSearchBar extends StatefulWidget {
  const PdfSearchBar({required this.searcher, required this.onClose, super.key});

  final PdfTextSearcher searcher;
  final VoidCallback onClose;

  @override
  State<PdfSearchBar> createState() => _PdfSearchBarState();
}

class _PdfSearchBarState extends State<PdfSearchBar> {
  final _text = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.searcher.addListener(_refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    widget.searcher.removeListener(_refresh);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _next() {
    if (widget.searcher.hasMatches) widget.searcher.goToNextMatch();
  }

  void _prev() {
    if (widget.searcher.hasMatches) widget.searcher.goToPrevMatch();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.searcher;
    final count = s.matches.length;
    final String status;
    if (_text.text.isEmpty) {
      status = '';
    } else if (count == 0) {
      status = s.isSearching ? 'Searching…' : 'No results';
    } else {
      status = '${(s.currentIndex ?? 0) + 1} / $count${s.isSearching ? '+' : ''}';
    }

    return Material(
      color: AppColors.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
                const SingleActivator(LogicalKeyboardKey.enter, shift: true): _prev,
                const SingleActivator(LogicalKeyboardKey.f3): _next,
                const SingleActivator(LogicalKeyboardKey.f3, shift: true): _prev,
              },
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      focusNode: _focus,
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(
                        hintText: 'Find in document',
                        prefixIcon: Icon(Icons.search_rounded, size: 20),
                      ),
                      onChanged: (value) {
                        s.startTextSearch(value, caseInsensitive: true);
                        setState(() {});
                      },
                      onSubmitted: (_) {
                        _next();
                        _focus.requestFocus();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 64),
                    child: Text(
                      status,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Previous (Shift+Enter)',
                    onPressed: count > 0 ? _prev : null,
                    icon: const Icon(Icons.keyboard_arrow_up_rounded),
                  ),
                  IconButton(
                    tooltip: 'Next (Enter)',
                    onPressed: count > 0 ? _next : null,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                  IconButton(
                    tooltip: 'Close (Esc)',
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 2,
            child: s.isSearching ? LinearProgressIndicator(value: s.searchProgress, minHeight: 2) : null,
          ),
        ],
      ),
    );
  }
}
