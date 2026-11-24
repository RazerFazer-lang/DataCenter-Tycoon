; Inno-Setup-Skript für den DataCenter-Tycoon-Launcher.
; Installiert nur den Launcher. Das Spiel lädt der Launcher selbst nach %LOCALAPPDATA%\DataCenterTycoon\game.
; Bauen: installer\build_installer.ps1 (oder ISCC.exe installer\DataCenterTycoon.iss)

#define AppName "DataCenter Tycoon Co-op"
#define AppExeName "DataCenterLauncher.exe"
#define BundleDir AddBackslash(SourcePath) + "..\dist\Freunde_Launcher"
#define SourceExe BundleDir + "\" + AppExeName

#if !FileExists(SourceExe)
  #error "Launcher-EXE fehlt: dist\Freunde_Launcher\DataCenterLauncher.exe. Erst im Launcher 'Freunde-Paket vorbereiten' ausführen."
#endif

; Versionsnummer aus der EXE (kommt aus <Version> in launcher\DataCenterLauncher.csproj).
#define AppVersion GetVersionNumbersString(SourceExe)
#if AppVersion == ""
  #define AppVersion "0.0.0.0"
#endif

[Setup]
; Feste AppId: Updates und Deinstallation erkennen damit dieselbe Installation. Nicht ändern.
AppId={{6F3B2C1A-8D4E-4B7F-9A21-3C5D7E9F1B42}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} Launcher {#AppVersion}
AppPublisher={#AppName}
VersionInfoVersion={#AppVersion}
VersionInfoProductName={#AppName}
VersionInfoDescription={#AppName} Setup
; Ohne Admin-Rechte: {autopf} wird zu %LOCALAPPDATA%\Programs.
PrivilegesRequired=lowest
DefaultDirName={autopf}\DataCenterTycoon
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist
OutputBaseFilename=DataCenterTycoon-Setup-{#AppVersion}
SetupIconFile=..\launcher\Assets\app_icon.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName}
; Läuft der Launcher noch, bietet das Setup an, ihn zu schließen.
CloseApplications=yes

[Languages]
Name: "german"; MessagesFile: "compiler:Languages\German.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceExe}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BundleDir}\release_repo.txt"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent