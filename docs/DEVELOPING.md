# Developing Folio PDF

Notes for building and changing Folio PDF. For what it does, see the [README](../README.md).

## Setup (one time)

You need **Flutter 3.47 or newer** (pdfrx requires it). Check with `flutter --version`, and run `flutter upgrade` if needed.

1. Open a terminal inside the project folder.
2. Get packages:
   ```
   flutter pub get
   ```
3. **Windows only:** turn on **Developer Mode** (Settings, System, For developers) and restart. pdfrx's build uses symbolic links and fails without it.

Then open the folder in VS Code (Flutter extension) or Android Studio and press Run, or use:
```
flutter run -d windows
flutter run -d <your-android-device-id>    # see `flutter devices`
```

If the Android or Windows platform folders are missing, generate them without touching `lib/`:
```
flutter create --platforms=android,windows --org com.folio --project-name folio_pdf .
```

## Building to share

See [BUILDING.md](../BUILDING.md) for the Windows installer, the signed Android APK and the release checklist. The Windows build can fail on very long paths or under a Temp folder, so build from a short path such as `C:\Users\<you>\folio`.

## App icon

The icon lives in `assets/icon/app_icon.png`. After changing it, regenerate the Android and Windows icons with:
```
dart run flutter_launcher_icons
```

## "Open with Folio PDF" on Android

`android/app/src/main/kotlin/com/folio/folio_pdf/MainActivity.kt` receives PDFs from other apps and copies them into Folio's storage. The two intent filters in `android_open_with_snippet.xml` must be inside the `<activity>` tag in `android/app/src/main/AndroidManifest.xml`.

## Renaming the app

- Android launcher name: `android:label` in `android/app/src/main/AndroidManifest.xml`
- Windows window title: `windows/runner/main.cpp` (the `window.Create(L"Folio PDF", ...)` line) and `title` in `lib/widgets/window_frame.dart`

## Project structure

```
lib/
  main.dart                    App entry, theme mode, Windows title bar
  theme.dart                   Material theme (light + dark) built from the palette
  design/palette.dart          Colors, spacing, radii, motion (FolioPalette, Dim)
  design/components.dart       Shared UI: glass panel, gold button, cards, toasts, sheets
  screens/home_screen.dart     Open card, continue reading, recent files
  screens/settings_screen.dart Theme and page style
  screens/viewer_screen.dart   Viewer, toolbar, zoom pill, shortcuts, save
  screens/organize_screen.dart Reorder, rotate, delete, merge and extract pages
  services/pdf_saver.dart      Save, Save as, share and export
  services/recent_files.dart   Recent files storage (shared_preferences)
  services/file_opener.dart    File picker
  services/settings.dart       Theme and page style preferences
  widgets/thumbnails_panel.dart
  widgets/search_bar.dart
  widgets/reading_filter.dart  Normal, sepia and dark page tint
  widgets/pdf_cover.dart       First-page preview for recent files
  widgets/window_frame.dart    Custom Windows title bar
  widgets/password_dialog.dart
docs/screenshots/              README images
```

## Ideas that need PDFium's lower-level API

These are available through the `pdfium_dart` bindings that pdfrx already ships: annotations (highlight, underline, ink, notes), form filling and visual signatures.

## Fonts

Inter and Fraunces are bundled in `assets/fonts/` (SIL Open Font License 1.1, see `assets/fonts/OFL.txt`).
