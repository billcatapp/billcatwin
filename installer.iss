; BillCat Windows installer (Inno Setup).
; Version is injected from CI via /DMyAppVersion=<version>; falls back to
; 0.0.0 for local test compiles.
#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif
#define MyAppName "BillCat"
#define MyAppPublisher "BillCat"
#define MyAppExeName "billcat.exe"
#define MyAppSourceDir "build\windows\x64\runner\Release"

[Setup]
; Fixed AppId so every version is recognized as an upgrade of the same
; install (not a side-by-side reinstall) - never change this.
AppId={{9F1A7D2E-4C3B-4E8F-9A6D-2B7E5C8F1A3D}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppUpdatesURL=https://github.com/billcatapp/billcatwin/releases
; Per-user install under LocalAppData: no admin/UAC prompt to install, and
; the app's own self-updater can overwrite files without elevation.
DefaultDirName={localappdata}\Programs\{#MyAppName}
DefaultGroupName={#MyAppName}
PrivilegesRequired=lowest
DisableProgramGroupPage=yes
OutputDir=installer_output
OutputBaseFilename=BillCat-Setup-{#MyAppVersion}
SetupIconFile=windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional icons:"

[Files]
Source: "{#MyAppSourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
