import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import 'screens/home_screen.dart';
import 'services/recent_files.dart';
import 'theme.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();
  await RecentFilesStore.instance.load();

  // On Windows, "Open with Folio PDF" passes the file path as the first argument.
  final initialFile = args.isNotEmpty && args.first.toLowerCase().endsWith('.pdf') ? args.first : null;

  runApp(FolioApp(initialFile: initialFile));
}

class FolioApp extends StatelessWidget {
  const FolioApp({this.initialFile, super.key});

  final String? initialFile;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Folio PDF',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      darkTheme: buildAppTheme(),
      themeMode: ThemeMode.dark,
      home: HomeScreen(initialFile: initialFile),
    );
  }
}
