import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';

import '../design/components.dart';
import '../services/unsaved_changes.dart';
import '../theme.dart';

bool get isDesktopWindow => Platform.isWindows;

/// Sets up the borderless Windows window. Call once before runApp.
Future<void> setUpDesktopWindow() async {
  if (!isDesktopWindow) return;
  await windowManager.ensureInitialized();
  await windowManager.setPreventClose(true);
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1180, 780),
      minimumSize: Size(440, 560),
      center: true,
      title: 'Folio PDF',
      titleBarStyle: TitleBarStyle.hidden,
      backgroundColor: Colors.transparent,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
}

/// Wraps the app in a custom Windows title bar that matches the theme.
/// On other platforms it just shows [child].
class WindowFrame extends StatefulWidget {
  const WindowFrame({required this.child, required this.navigatorKey, super.key});

  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<WindowFrame> createState() => _WindowFrameState();
}

class _WindowFrameState extends State<WindowFrame> with WindowListener {
  @override
  void initState() {
    super.initState();
    if (isDesktopWindow) windowManager.addListener(this);
  }

  @override
  void dispose() {
    if (isDesktopWindow) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    if (!UnsavedChanges.hasUnsaved.value) {
      await windowManager.destroy();
      return;
    }
    final ctx = widget.navigatorKey.currentContext;
    if (ctx == null) {
      await windowManager.destroy();
      return;
    }
    final leave = await showDialog<bool>(
      context: ctx,
      builder: (context) => AlertDialog(
        title: const Text('Close without saving?'),
        content: const Text('You have unsaved changes. If you close Folio now, they will be lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep editing')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Close anyway')),
        ],
      ),
    );
    if (leave == true) await windowManager.destroy();
  }

  @override
  Widget build(BuildContext context) {
    if (!isDesktopWindow) return widget.child;
    final p = context.pal;
    return Column(
      children: [
        Container(
          height: 38,
          color: p.background,
          child: WindowCaption(
            brightness: p.brightness,
            backgroundColor: Colors.transparent,
            title: Row(
              children: [
                const FolioMark(size: 18),
                const SizedBox(width: 10),
                Text(
                  'Folio PDF',
                  style: TextStyle(
                    fontFamily: FolioFonts.ui,
                    color: p.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}
