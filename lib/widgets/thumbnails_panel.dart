import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import '../theme.dart';
import 'reading_filter.dart';

/// Vertical list of page thumbnails. Tapping one jumps to that page.
class ThumbnailsPanel extends StatefulWidget {
  const ThumbnailsPanel({
    required this.documentRef,
    required this.currentPage,
    required this.onPageSelected,
    required this.darkReading,
    super.key,
  });

  final PdfDocumentRef documentRef;
  final int currentPage;
  final ValueChanged<int> onPageSelected;
  final bool darkReading;

  @override
  State<ThumbnailsPanel> createState() => _ThumbnailsPanelState();
}

class _ThumbnailsPanelState extends State<ThumbnailsPanel> {
  static const _itemExtent = 214.0;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealCurrent(animate: false));
  }

  @override
  void didUpdateWidget(covariant ThumbnailsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentPage != widget.currentPage) _revealCurrent();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Keeps the current page's thumbnail in view as the user scrolls the document.
  void _revealCurrent({bool animate = true}) {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final top = (widget.currentPage - 1) * _itemExtent;
    final bottom = top + _itemExtent;
    if (top >= pos.pixels && bottom <= pos.pixels + pos.viewportDimension) return;
    final target = (top - pos.viewportDimension / 2 + _itemExtent / 2).clamp(0.0, pos.maxScrollExtent);
    if (animate) {
      _scroll.animateTo(target, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    } else {
      _scroll.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surface,
      child: PdfDocumentViewBuilder(
        documentRef: widget.documentRef,
        builder: (context, document) {
          if (document == null) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          }
          return ListView.builder(
            controller: _scroll,
            itemExtent: _itemExtent,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: document.pages.length,
            itemBuilder: (context, index) {
              final pageNumber = index + 1;
              final selected = pageNumber == widget.currentPage;
              return Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => widget.onPageSelected(pageNumber),
                  child: Column(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: selected ? AppColors.accent : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: ReadingFilter(
                            enabled: widget.darkReading,
                            child: PdfPageView(
                              key: ValueKey('thumb_${document.hashCode}_$index'),
                              document: document,
                              pageNumber: pageNumber,
                              maximumDpi: 72,
                              alignment: Alignment.center,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$pageNumber',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected ? AppColors.accent : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
