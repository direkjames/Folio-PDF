# Folio PDF

A free, ad-free PDF viewer (and soon editor) for **Android** and **Windows**, built with Flutter and [pdfrx](https://pub.dev/packages/pdfrx) (PDFium, MIT license).

## Phase 1 features (this version)

- Open PDFs with the system file picker, including password-protected files
- Smooth scrolling, pinch/scroll zoom, zoom buttons, fit width, fit page
- Page thumbnails (side panel on wide screens, slide-out drawer on phones)
- Find in document with match count and next/previous
- Dark pages toggle (inverts the PDF for night reading; remembered between sessions)
- Recent files list that reopens each file on the page you left off
- Dark UI with `#FFE566` accent throughout

## Phase 2 features (editing, part 1)

- **Organize pages** (grid icon in the viewer): drag to reorder, rotate, delete, duplicate, undo
- **Merge:** "Add PDF" in Organize appends pages from one or more other PDFs
- **Split / extract:** select pages and save them as a new PDF
- **Save** (`Ctrl+S`) and **Save as** (`Ctrl+Shift+S`), with a warning if you leave with unsaved changes
- On Android, apps can't save into any folder they like, so Save keeps the edited copy inside Folio and **Export** opens the share sheet (Files, Drive, chat apps, etc.)

Keyboard shortcuts on Windows: `Ctrl+F` find, `Enter` / `Shift+Enter` next/previous match, `Esc` close find, `Ctrl+` / `Ctrl-` zoom, `Ctrl+0` fit width, `Ctrl+G` go to page, `Ctrl+S` save, `Ctrl+Shift+S` save as.

## Setup (one time)

You need **Flutter 3.47 or newer** (pdfrx requires it). Check with `flutter --version`, and run `flutter upgrade` if needed.

1. Unzip this folder and open a terminal inside it (`folio_pdf`).
2. Generate the Android and Windows platform folders. This does not touch the existing `lib/` code:
   ```
   flutter create --platforms=android,windows --org com.folio --project-name folio_pdf .
   ```
3. Get packages:
   ```
   flutter pub get
   ```
4. **Windows only:** turn on **Developer Mode** (Settings → System → For developers) and restart. pdfrx's build uses symbolic links and fails without it.

Then open the folder in VS Code (Flutter extension) or Android Studio and press Run, or use:
```
flutter run -d windows
flutter run -d <your-android-device-id>    # see `flutter devices`
```

## Building to share with friends

**Android APK**
```
flutter build apk --release
```
Output: `build/app/outputs/flutter-apk/app-release.apk`. Friends install it by opening the file and allowing "Install unknown apps" for their browser or file manager.

Important: by default Flutter signs release builds with your machine's debug key. That works, but if you ever build from a different computer, friends will have to uninstall before they can update. Before sharing widely, create your own signing key once and keep it safe: https://docs.flutter.dev/deployment/android#sign-the-app

**Windows**
```
flutter build windows --release
```
Output: `build\windows\x64\runner\Release\`. Zip that **whole folder** (the `.exe` needs the DLLs and `data` folder next to it). Friends unzip and run `folio_pdf.exe`. Windows SmartScreen may warn because the app isn't code-signed; they click "More info → Run anyway".

## App icon

The icon lives in `assets/icon/app_icon.png`. After changing it, regenerate the Android and Windows icons with:
```
dart run flutter_launcher_icons
```

## "Open with Folio PDF" on Android

`android/app/src/main/kotlin/com/folio/folio_pdf/MainActivity.kt` receives PDFs from other apps and copies them into Folio's storage. The two intent filters in `android_open_with_snippet.xml` must be inside the `<activity>` tag in `android/app/src/main/AndroidManifest.xml`.

## Renaming the app

- Android launcher name: `android:label` in `android/app/src/main/AndroidManifest.xml`
- Windows window title: `windows/runner/main.cpp` (the `window.Create(L"folio_pdf", ...)` line)
- App icon: the easiest route is the `flutter_launcher_icons` package

## Project structure

```
lib/
  main.dart                    App entry, dark theme
  theme.dart                   Colors (accent #FFE566) and Material theme
  screens/home_screen.dart     Open button + recent files
  screens/viewer_screen.dart   Viewer, toolbar, zoom pill, shortcuts, save
  screens/organize_screen.dart Reorder/rotate/delete/merge/extract pages
  services/pdf_saver.dart      Save, Save as, share/export
  services/recent_files.dart   Recent files storage (shared_preferences)
  services/file_opener.dart    File picker
  widgets/thumbnails_panel.dart
  widgets/search_bar.dart
  widgets/reading_filter.dart  Dark pages color inversion
  widgets/password_dialog.dart
```

## Roadmap: rest of Phase 2

These need PDFium's lower-level API (available through the `pdfium_dart` bindings that pdfrx already ships):
- **Annotations:** highlight, underline, freehand ink, sticky notes, text boxes (`FPDFAnnot_*` functions), saved as real PDF annotations so they show up in other readers
- **Form filling:** PDFium's form functions (`FORM_*`, `FPDFAnnot_SetStringValue`)
- **Signatures:** a drawn or imported signature image stamped onto the page (visual signature, not a certificate-based digital signature)

