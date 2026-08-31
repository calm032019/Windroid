; Windroid setup wizard (Inno Setup 6).
; Wraps installer/install.ps1 in a professional wizard with a system-check
; page that advises on WSL/virtualization state BEFORE anything is touched.
; Build with scripts/make-setup.ps1 (passes ArtifactDir/OutputDir defines).
;
; Per-user install (WSL is per-user; no UAC needed). The heavy lifting —
; kernel, .wslconfig merge, distro import, first boot, smoke test — stays
; in install.ps1 so the console zip flow and this wizard share one engine.

#ifndef ArtifactDir
  #error Pass /DArtifactDir=<dir with versions.json + artifacts>
#endif
#ifndef OutputDir
  #define OutputDir "."
#endif
#ifndef InstallRootOverride
  #define InstallRootArgs ""
#else
  ; quotes doubled: this lands inside the [Run] Parameters "..." value
  #define InstallRootArgs ' -InstallRoot ""' + InstallRootOverride + '""'
#endif

[Setup]
AppId={{7E1D51B0-9C3A-4C1B-A1AB-2B7E0F8B11D7}
AppName=Windroid
AppVersion=0.1.0
AppPublisher=Windroid
AppPublisherURL=https://github.com/calm032019/Windroid
DefaultDirName={localappdata}\Windroid\payload
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir={#OutputDir}
OutputBaseFilename=Windroid-Setup-0.1.0
SetupIconFile=..\assets\windroid.ico
UninstallDisplayIcon={app}\assets\windroid.ico
UninstallDisplayName=Windroid (Android subsystem)
WizardStyle=modern
WizardImageFile=..\assets\wizard-large.bmp
WizardSmallImageFile=..\assets\wizard-small.bmp
; The big artifacts are already gzip/vhdx-compressed - recompressing wastes
; 10+ minutes of build for ~0 gain.
Compression=lzma2/fast
SolidCompression=no

[Files]
Source: "install.ps1"; DestDir: "{app}\installer"
Source: "uninstall.ps1"; DestDir: "{app}\installer"
Source: "..\scripts\windroid.ps1"; DestDir: "{app}\scripts"
Source: "..\scripts\bench.ps1"; DestDir: "{app}\scripts"
Source: "..\windows\tray\windroid-tray.ps1"; DestDir: "{app}\windows\tray"
Source: "..\assets\windroid.ico"; DestDir: "{app}\assets"
Source: "{#ArtifactDir}\versions.json"; DestDir: "{app}\artifacts"
Source: "{#ArtifactDir}\bzImage-windroid-*"; DestDir: "{app}\artifacts"; Flags: nocompression
Source: "{#ArtifactDir}\modules-windroid-*.vhdx"; DestDir: "{app}\artifacts"; Flags: nocompression
Source: "{#ArtifactDir}\windroid-rootfs-vanilla-*.tar.gz"; DestDir: "{app}\artifacts"; Flags: nocompression

[Run]
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\installer\install.ps1"" -ArtifactSource ""{app}\artifacts""{#InstallRootArgs}"; \
  StatusMsg: "Setting up the Android subsystem (kernel, image import, first boot - a few minutes)..."; \
  Flags: waituntilterminated

[UninstallRun]
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\installer\uninstall.ps1"""; \
  Flags: waituntilterminated; RunOnceId: "WindroidUninstall"

[Code]
var
  CheckPage: TWizardPage;
  WslPresent, VirtPresent, RebootLikely: Boolean;

function RunHidden(const Cmd, Params: string): Integer;
var
  R: Integer;
begin
  if Exec(Cmd, Params, '', SW_HIDE, ewWaitUntilTerminated, R) then
    Result := R
  else
    Result := -1;
end;

procedure ProbeSystem();
begin
  { wsl --status exits 0 only when WSL is installed and functional. }
  WslPresent := RunHidden(ExpandConstant('{sys}\wsl.exe'), '--status') = 0;
  { HypervisorPresent = virtualization enabled + hypervisor running. }
  VirtPresent := RunHidden('powershell.exe',
    '-NoProfile -Command "exit [int](-not (Get-CimInstance Win32_ComputerSystem).HypervisorPresent)"') = 0;
  RebootLikely := not WslPresent;
end;

procedure AddPara(Page: TWizardPage; var Y: Integer; const S: string; Warn: Boolean);
var
  L: TNewStaticText;
begin
  L := TNewStaticText.Create(Page);
  L.Parent := Page.Surface;
  L.Top := Y;
  L.Width := Page.SurfaceWidth;
  L.WordWrap := True;
  L.AutoSize := True;
  L.Caption := S;
  if Warn then
    L.Font.Style := [fsBold];
  Y := L.Top + L.Height + ScaleY(10);
end;

procedure InitializeWizard();
var
  Y: Integer;
begin
  ProbeSystem();
  CheckPage := CreateCustomPage(wpWelcome, 'System check',
    'Windroid checked this PC before changing anything.');
  Y := 0;
  if VirtPresent then
    AddPara(CheckPage, Y, 'OK - Hardware virtualization is enabled.', False)
  else
    AddPara(CheckPage, Y,
      'PROBLEM - Hardware virtualization is disabled. Installing now is NOT ' +
      'recommended: Windroid cannot run without it. Enable VT-x / AMD-V in ' +
      'your BIOS/UEFI firmware first, then run this setup again.', True);

  if WslPresent then
    AddPara(CheckPage, Y,
      'OK - Windows Subsystem for Linux is already enabled. No reboot is ' +
      'expected; installation normally completes in a few minutes.', False)
  else
    AddPara(CheckPage, Y,
      'NOTE - WSL is not enabled on this PC yet. Setup will enable it for ' +
      'you, but Windows will require a RESTART partway through. After ' +
      'restarting, run this setup again - it resumes exactly where it left ' +
      'off. If you would rather not change Windows features right now, ' +
      'click Cancel.', True);

  AddPara(CheckPage, Y,
    'Installation needs about 15 GB of free disk space and downloads ' +
    'nothing - everything ships inside this setup.', False);
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if (CheckPage <> nil) and (CurPageID = CheckPage.ID) and (not VirtPresent) then
    Result := MsgBox(
      'Virtualization is disabled, so Windroid will not be able to run. ' +
      'Continue anyway?', mbConfirmation, MB_YESNO) = IDYES;
end;
