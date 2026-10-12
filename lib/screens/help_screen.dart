import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// "How to use" guide. Text adapts to Windows vs Android where they differ.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HelpScreen()));

  @override
  Widget build(BuildContext context) {
    final android = Platform.isAndroid;
    final sections = <_Section>[
      _Section(
        icon: Icons.folder_open_rounded,
        title: 'Opening a PDF',
        steps: [
          'Tap **Open PDF** on the home screen and pick a file.',
          'Files you open appear under **Recent**. Tap one to reopen it on the page where you left off.',
          'Tap the **×** next to a recent file to remove it from the list. This never deletes the file itself.',
          'Password-protected PDFs ask for their password when opened.',
          if (android)
            'You can also open PDFs from other apps: tap a PDF in Files, Gmail, Messenger, etc., then choose **Folio PDF**. Or use **Share → Folio PDF**.'
          else
            'You can also right-click a PDF in File Explorer, choose **Open with**, and pick Folio PDF.',
        ],
      ),
      _Section(
        icon: Icons.chrome_reader_mode_outlined,
        title: 'Reading',
        steps: [
          android
              ? 'Scroll to move through pages. Pinch with two fingers to zoom.'
              : 'Scroll with the mouse wheel. Press **Ctrl +** and **Ctrl −** to zoom.',
          'The pill at the bottom shows the page number. Tap it to jump to a page. Use **−** and **+** to zoom, and tap the percentage to fit the page width.',
          'The **⋮** menu has Fit width, Fit page, and First / Last page.',
          android
              ? 'Tap the **sidebar icon** to open page thumbnails. Tap a thumbnail to go to that page.'
              : 'Click the **sidebar icon** to show or hide page thumbnails on the left. Click one to go to that page.',
        ],
      ),
      _Section(
        icon: Icons.search_rounded,
        title: 'Finding text',
        steps: [
          android ? 'Tap the **search icon** and type a word.' : 'Click the **search icon** or press **Ctrl+F**, then type.',
          'Matches are highlighted in yellow. The counter shows which match you are on, e.g. "3 / 12".',
          android
              ? 'Use the **up** and **down arrows** to move between matches.'
              : 'Press **Enter** for the next match and **Shift+Enter** for the previous one. **Esc** closes search.',
          'Scanned PDFs (photos of paper) have no searchable text, so search won\'t find anything in them.',
        ],
      ),
      _Section(
        icon: Icons.dark_mode_outlined,
        title: 'Dark pages',
        steps: [
          'Tap the **moon icon** to turn white pages dark for night reading. Tap again to switch back.',
          'This only changes how pages look on screen. Your file is not changed.',
          'Photos inside the PDF will look inverted while dark pages is on.',
        ],
      ),
      _Section(
        icon: Icons.auto_awesome_mosaic_outlined,
        title: 'Organizing pages',
        steps: [
          'Tap the **Organize pages** icon in the viewer\'s top bar.',
          'To **move** a page, drag it by the **⠿ handle** on the right.',
          'To **rotate**, tap the rotate icon on a page. The **⋮** on each page also has Rotate left, Duplicate and Delete.',
          'To work on several pages at once, tick their **checkboxes** (or tap **Select all**). Then use the buttons at the top to rotate, delete, or save them as a new PDF.',
          'To **combine PDFs**, tap **Add PDF** (shown when nothing is selected) and pick one or more files. Their pages are added at the end, and you can drag them anywhere.',
          'Made a mistake? Tap **Undo**.',
          'Tap **Done** to apply your changes to the document. Then save it (see below).',
        ],
      ),
      _Section(
        icon: Icons.call_split_rounded,
        title: 'Splitting a PDF',
        steps: [
          'Open **Organize pages** and tick the pages you want to take out.',
          android
              ? 'Tap the **split icon**. A share menu opens, where you can save the new PDF to Files or Drive, or send it to someone.'
              : 'Click the **split icon** and choose where to save the new PDF. Your original file stays as it is.',
        ],
      ),
      _Section(
        icon: Icons.save_outlined,
        title: 'Saving',
        steps: [
          'A **yellow dot** next to the file name means you have unsaved changes.',
          if (!android) ...[
            'Click the **save icon** or press **Ctrl+S** to save over the original file.',
            'To keep the original untouched, use **⋮ → Save as…** (or **Ctrl+Shift+S**) and pick a new name.',
          ] else ...[
            'Tap the **save icon** to save your changes inside Folio. The file in **Recent** will show your edits.',
            'Android doesn\'t let apps save into any folder they like. To get the edited PDF into your Files, Drive, or a chat, use **⋮ → Export…** and pick where it goes.',
          ],
          'If you try to leave with unsaved changes, Folio asks whether to save first.',
        ],
      ),
      if (!android)
        const _Section(
          icon: Icons.keyboard_outlined,
          title: 'Keyboard shortcuts',
          shortcuts: [
            ('Ctrl+F', 'Find text'),
            ('Enter / Shift+Enter', 'Next / previous match'),
            ('Esc', 'Close find'),
            ('Ctrl + / Ctrl −', 'Zoom in / out'),
            ('Ctrl+0', 'Fit width'),
            ('Ctrl+G', 'Go to page'),
            ('Ctrl+S', 'Save'),
            ('Ctrl+Shift+S', 'Save as'),
          ],
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('How to use Folio PDF'),
        bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider()),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            itemCount: sections.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              if (i == 0) {
                return const Padding(
                  padding: EdgeInsets.fromLTRB(4, 0, 4, 4),
                  child: Text(
                    'Folio PDF is free, has no ads, and doesn\'t need an account. Your files stay on your device.',
                    style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                  ),
                );
              }
              return _SectionCard(section: sections[i - 1], initiallyExpanded: i == 1);
            },
          ),
        ),
      ),
    );
  }
}

class _Section {
  const _Section({required this.icon, required this.title, this.steps = const [], this.shortcuts = const []});

  final IconData icon;
  final String title;
  final List<String> steps;
  final List<(String, String)> shortcuts;
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section, required this.initiallyExpanded});

  final _Section section;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: AppColors.accent,
        collapsedIconColor: AppColors.textSecondary,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(section.icon, color: AppColors.accent, size: 20),
        ),
        title: Text(section.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5)),
        children: [
          for (var i = 0; i < section.steps.length; i++) _Step(number: i + 1, text: section.steps[i]),
          for (final (keys, action) in section.shortcuts) _ShortcutRow(keys: keys, action: action),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(top: 1),
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.surfaceHigh, shape: BoxShape.circle),
            child: Text(
              '$number',
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.accent),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text.rich(_boldMarkup(text), style: const TextStyle(height: 1.45))),
        ],
      ),
    );
  }

  /// Turns **bold** markers into bold spans.
  static TextSpan _boldMarkup(String text) {
    final parts = text.split('**');
    return TextSpan(
      children: [
        for (var i = 0; i < parts.length; i++)
          TextSpan(
            text: parts[i],
            style: i.isOdd ? const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary) : null,
          ),
      ],
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.keys, required this.action});

  final String keys;
  final String action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(keys, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(action, style: const TextStyle(color: AppColors.textSecondary))),
        ],
      ),
    );
  }
}
