# Building Folio PDF

Author: direk james

Requires Flutter 3.47 or newer (`flutter --version`). Run `flutter pub get` once first.

## Windows installer

Needs a Windows PC with **Developer Mode** on (Settings > System > For developers) and
**Visual Studio 2022** with the "Desktop development with C++" workload.

1. Build the app:
   ```
   flutter build windows --release
   ```
   Output: `build\windows\x64\runner\Release\` (this folder alone also works as a portable zip).
2. Install [Inno Setup 6](https://jrsoftware.org/isinfo.php) (free).
3. Check `AppVersion` at the top of `installer\folio_pdf.iss` matches `version:` in `pubspec.yaml`.
4. Open `installer\folio_pdf.iss` in Inno Setup and press **Compile** (Ctrl+F9). Or from a terminal:
   ```
   "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\folio_pdf.iss
   ```
5. The installer is created at `installer\Output\FolioPDF-Setup-<version>.exe`.

Windows SmartScreen may warn about an unsigned installer: click **More info > Run anyway**.

## Android APK

Needs Android Studio (for the Android SDK) and `flutter doctor` showing no Android issues.

### One time: create your release key
Keep this file and its passwords safe and backed up. If you lose it, you cannot update the app for people who installed it.
```
keytool -genkey -v -keystore C:\keys\folio-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias folio
```
Then copy `android\key.properties.example` to `android\key.properties` and fill in the passwords and the path.
Both the keystore and `key.properties` are git-ignored, never commit them.

### Build
```
flutter build apk --release
```
Output: `build\app\outputs\flutter-apk\app-release.apk`. Send it to friends, they open it and allow "Install unknown apps".

Smaller per-phone APKs: `flutter build apk --release --split-per-abi` (most modern phones use `app-arm64-v8a-release.apk`).

For the Google Play Store, build an app bundle instead: `flutter build appbundle --release`
(output `build\app\outputs\bundle\release\app-release.aab`).

Without `android/key.properties` the build still works but is signed with a debug key.
Friends would have to uninstall before updating if you later switch keys, so create the release key before sharing.

## Before each release
1. Bump `version:` in `pubspec.yaml` (e.g. `0.2.1+3`; the number after `+` must go up for every Android release).
2. Bump `AppVersion` in `installer\folio_pdf.iss` and the version text in `lib/screens/settings_screen.dart`.
3. Run `flutter analyze` and `flutter test`.
