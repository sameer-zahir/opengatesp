; OpenGateSP installer (Inno Setup 6). Per-user, no admin required.
; Build with:  pwsh installer\Build-Installer.ps1   (or: ISCC installer\OpenGateSP.iss)

#define MyAppName "OpenGateSP"
#define MyAppVersion "0.4.0"
#define MyAppPublisher "Sameer Zahir"
#define MyAppURL "https://sameerzahir.com"
#define MyAppRepo "https://github.com/sameer-zahir/opengatesp"
#define MyAppExe "OpenGateSP.exe"

[Setup]
AppId={{B8E7C4A2-9D31-4F6B-A2E5-7C1D0F9A3B6E}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppRepo}
AppUpdatesURL={#MyAppRepo}/releases
; Per-user install: no UAC prompt, no admin needed.
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#MyAppExe}
UninstallDisplayName={#MyAppName}
OutputDir=..\dist
OutputBaseFilename=OpenGateSP-Setup
SetupIconFile=..\tools\opengatesp.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
VersionInfoVersion={#MyAppVersion}.0
VersionInfoProductName={#MyAppName}
VersionInfoCompany={#MyAppPublisher}
LicenseFile=..\LICENSE

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Files]
Source: "..\dist\{#MyAppExe}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\Start-OpenGateSP.cmd"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\CHANGELOG.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\module\*"; DestDir: "{app}\module"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\gui\*"; DestDir: "{app}\gui"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\tools\*"; DestDir: "{app}\tools"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\docs\*"; DestDir: "{app}\docs"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\scripts\*"; DestDir: "{app}\scripts"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"; Comment: "Open OpenGateSP"
Name: "{group}\{#MyAppName} on GitHub"; Filename: "{#MyAppRepo}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExe}"; Description: "Launch {#MyAppName} now"; Flags: nowait postinstall skipifsilent

[Code]
function PowerShell7Installed(): Boolean;
var p: String;
begin
  Result := RegQueryStringValue(HKLM, 'SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\pwsh.exe', '', p)
         or RegQueryStringValue(HKCU, 'SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\pwsh.exe', '', p)
         or FileExists(ExpandConstant('{commonpf}\PowerShell\7\pwsh.exe'))
         or FileExists(ExpandConstant('{localappdata}\Microsoft\PowerShell\7\pwsh.exe'));
end;

function InitializeSetup(): Boolean;
begin
  Result := True;
  if not PowerShell7Installed() then
    MsgBox('OpenGateSP runs on PowerShell 7, which was not detected on this PC.'
      + #13#10 + #13#10
      + 'You can install OpenGateSP now, but install PowerShell 7 before launching it:'
      + #13#10 + '    winget install Microsoft.PowerShell'
      + #13#10 + 'or download it from https://aka.ms/powershell',
      mbInformation, MB_OK);
end;
