import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import 'screens/home_screen.dart';
import 'services/recent_files.dart';
import 'services/settings.dart';
import 'theme.dart';
import 'widgets/window_frame.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();
  await Future.wait([RecentFilesStore.instance.load(), SettingsStore.instance.load()]);
  await setUpDesktopWindow();

  // Draw behind the status and navigation bars on Android.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // On Windows, "Open with Folio PDF" passes the file path as the first argument.
  final initialFile = args.isNotEmpty && args.first.toLowerCase().endsWith('.pdf') ? args.first : null;

  runApp(FolioApp(initialFile: initialFile));
}

class FolioApp extends StatefulWidget {
  const FolioApp({this.initialFile, super.key});

  final String? initialFile;

  @override
  State<FolioApp> createState() => _FolioAppState();
}

class _FolioAppState extends State<FolioApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _settings = SettingsStore.instance;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) => MaterialApp(
        title: 'Folio PDF',
        debugShowCheckedModeBanner: false,
        navigatorKey: _navigatorKey,
        theme: buildAppTheme(Brightness.light),
        darkTheme: buildAppTheme(Brightness.dark),
        themeMode: _settings.themeMode,
        builder: (context, child) {
          final p = context.pal;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarContrastEnforced: false,
              statusBarIconBrightness: p.isDark ? Brightness.light : Brightness.dark,
              systemNavigationBarIconBrightness: p.isDark ? Brightness.light : Brightness.dark,
            ),
            child: WindowFrame(navigatorKey: _navigatorKey, child: child ?? const SizedBox()),
          );
        },
        home: HomeScreen(initialFile: widget.initialFile),
      ),
    );
  }
}
