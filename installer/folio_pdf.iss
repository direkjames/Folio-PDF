; Folio PDF - Windows installer script for Inno Setup 6 (free: https://jrsoftware.org/isinfo.php)
;
; How to build the installer:
;   1. flutter build windows --release
;   2. Open this file in Inno Setup and press Compile (or Ctrl+F9)
;   3. The installer appears in installer\Output\
;
; Before each new release, bump AppVersion below (match "version:" in pubspec.yaml).

#define AppName "Folio PDF"
#define AppVersion "0.2.0"
#define AppPublisher "Folio PDF"
#define AppExeName "folio_pdf.exe"
#define BuildDir "..\build\windows\x64\runner\Release"

[Setup]
; AppId identifies the app for updates/uninstall. Never change it once you've shared an installer.
AppId={{9E621EF6-C7FC-4270-8850-02497254ADC9}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName}
SetupIconFile=..\windows\runner\resources\app_icon.ico
OutputDir=Output
OutputBaseFilename=FolioPDF-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Installs just for the current user by default (no admin password needed).
; The user can choose "install for all users" instead, which asks for admin.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
; Tells Windows to refresh file associations ("Open with") after install/uninstall.
ChangesAssociations=yes
; Updating: close a running Folio first.
CloseApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; Everything Flutter built: the .exe, DLLs (including PDFium) and the data folder.
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Microsoft C++ runtime DLLs that Flutter apps need. Copied from your PC at compile time,
; so friends without the "Visual C++ Redistributable" can still run Folio.
Source: "C:\Windows\System32\msvcp140.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "C:\Windows\System32\vcruntime140.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "C:\Windows\System32\vcruntime140_1.dll"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Registry]
; Adds Folio PDF to the "Open with" menu for PDF files (it doesn't take over as the default;
; users can pick Folio as default themselves via Open with > Choose another app).
Root: HKA; Subkey: "Software\Classes\.pdf\OpenWithProgids"; ValueType: string; ValueName: "FolioPDF.Document"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\FolioPDF.Document"; ValueType: string; ValueName: ""; ValueData: "PDF Document"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\FolioPDF.Document\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#AppExeName},0"
Root: HKA; Subkey: "Software\Classes\FolioPDF.Document\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExeName}"" ""%1"""
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExeName}\SupportedTypes"; ValueType: string; ValueName: ".pdf"; ValueData: ""; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExeName}"; ValueType: string; ValueName: "FriendlyAppName"; ValueData: "{#AppName}"; Flags: uninsdeletekey

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
