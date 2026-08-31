# Upstream facts — verified 2026-08-30

Working agreement #1 says never invent paths, flags, prop keys, or config
names. This file is the ledger: every upstream value our code depends on,
with where it was verified. Anything tagged **UNVERIFIED** must be confirmed
on a real machine (Phase 0) before automation treats it as truth. Re-verify
this file at the start of each phase — versions drift (agreement #2).

## 1. WSL2 kernel (microsoft/WSL2-Linux-Kernel)

- **Current series: 6.18.x** (default branch `linux-msft-wsl-6.18.y`; newest
  tag at verification time `linux-msft-wsl-6.18.40.1`, 2026-08-01). The
  `linux-msft-wsl-6.6.y` branch is still maintained (`6.6.123.2`,
  2026-03-05). Source: repo /releases and /tags.
- **Config path:** `Microsoft/config-wsl` is a **symlink** to
  `arch/x86/configs/config-wsl` on both branches. A git clone resolves it;
  raw single-file HTTP downloads must fetch the real path.
  (`CONFIG_LOCALVERSION="-microsoft-standard-WSL2"`.)
- **Binder is compiled out of stock kernels:**
  `# CONFIG_ANDROID_BINDER_IPC is not set` in config-wsl on both 6.6.y and
  6.18.y — the custom kernel is genuinely required.
- **Binder Kconfig options exist with these exact names**
  (drivers/android/Kconfig): `CONFIG_ANDROID_BINDER_IPC`,
  `CONFIG_ANDROID_BINDERFS`, `CONFIG_ANDROID_BINDER_DEVICES`
  (default `"binder,hwbinder,vndbinder"`), plus
  `ANDROID_BINDER_IPC_SELFTEST`. ddcash additionally sets
  `CONFIG_ANDROID_BINDER_IPC_RUST=n` and
  `CONFIG_ANDROID_BINDER_ALLOC_KUNIT_TEST=n`.
- **ashmem does not exist in 6.6+** (`drivers/staging/android/` gone; zero
  ASHMEM lines in config-wsl). Waydroid copes: if `/dev/ashmem` is absent it
  sets `sys.use_memfd=true` in waydroid_base.prop
  (waydroid source `tools/helpers/lxc.py` L261-262). Do not chase ashmem.
- **Documented build flow** (repo README, same on 6.6.y and 6.18.y):
  ```bash
  sudo apt install build-essential flex bison dwarves libssl-dev libelf-dev cpio qemu-utils
  make KCONFIG_CONFIG=Microsoft/config-wsl && make INSTALL_MOD_PATH="$PWD/modules" modules_install
  sudo ./Microsoft/scripts/gen_modules_vhdx.sh "$PWD/modules" $(make -s kernelrelease) modules.vhdx
  ```
- **Tag matching** (harvested from ddcash Install-Waydroid.ps1 L121-146):
  `uname -r` → strip `-microsoft-standard-WSL2` (and trailing `+`) → look
  for exact `linux-msft-wsl-<ver>` tag → fall back to newest tag in the same
  `major.minor`. A trailing `+` in `uname -r` means a custom kernel is
  already active.

## 2. `.wslconfig` (learn.microsoft.com/en-us/windows/wsl/wsl-config, doc dated 2026-04-15)

| Setting | Section | Exact syntax |
|---|---|---|
| Custom kernel | `[wsl2]` | `kernel=C:\\path\\bzImage` (escaped backslashes) |
| Kernel modules VHD | `[wsl2]` | `kernelModules=C:\\path\\modules.vhdx` |
| Memory cap | `[wsl2]` | `memory=4GB` (default 50% of RAM) |
| autoMemoryReclaim | `[experimental]` | `disabled`/`gradual`/`dropCache` (doc default now `dropCache`) |
| sparseVhd | `[experimental]` | `sparseVhd=true` |
| networkingMode | `[wsl2]` | `none`/`nat` (default)/`bridged` (deprecated)/`mirrored`/`virtioproxy` |

- `wsl --shutdown` then restart required for `.wslconfig` changes.
- ddcash also sets `vmIdleTimeout=-1` in `[wsl2]` to stop WSL tearing the VM
  down ~60 s after the last wsl.exe connection closes. UNVERIFIED against
  Microsoft docs (harvested working value) — confirm in Phase 0.
- WSL Settings GUI has Developer → `CustomKernelPathExpander` +
  `CustomKernelModulesPathExpander` (verified in microsoft/WSL
  `wslsettings/Views/Settings/DeveloperPage.xaml`); Microsoft now recommends
  the GUI over hand-editing.

## 3. `wsl --import` and `.wsl` distro files

- `wsl --import <DistroName> <InstallLocation> <FileName>` (options
  `--vhd`, `--version <1|2>`; `-` = stdin). Also
  `wsl --import-in-place <name> <file.vhdx>`.
- `.wsl` files: **WSL ≥ 2.4.4**. A `.wsl` is a tar (gzip recommended) whose
  root is the filesystem root; must contain `/etc/wsl-distribution.conf`
  (root:root 0644) with `[oobe] command/defaultUid/defaultName`,
  `[shortcut] enabled/icon` (`.ico`, ≤10 MB → Start Menu shortcut),
  `[windowsterminal] enabled/profileTemplate`. Must NOT contain a kernel,
  initramfs, `/etc/resolv.conf`, or password hashes. Install by double-click
  or `wsl --install --from-file <file>`. Recommended pack command:
  `tar --numeric-owner --absolute-names -c * | gzip --best > ../install.tar.gz`.
  Source: learn.microsoft.com/en-us/windows/wsl/build-custom-distro.

## 4. WSLg (microsoft/wslg + microsoft/weston-mirror)

- `WSLGd` launches Weston (+XWayland), PulseAudio, and mstsc.exe RDP.
- App list → Start Menu: Weston RDP backend plugin enumerates `.desktop`
  files and sends them over an RDP dynamic virtual channel; Windows-side
  `WSLDVCPlugin` creates Start Menu links.
- **Scanned dirs** (weston-mirror `rdprail-shell/app-list.c` ~L931-941):
  `/usr/share/applications`, `/usr/local/share/applications`,
  `/var/lib/flatpak/exports/share/applications`. **`XDG_DATA_DIRS` support
  is a TODO** — `~/.local/share/applications` is NOT scanned.
- **Consequence:** Waydroid writes per-app `.desktop` files to
  `$XDG_DATA_HOME/applications` (`~/.local/share/applications/`), pattern
  `waydroid.<packageName>.desktop`, `Exec=waydroid app launch <pkg>`
  (waydroid `tools/services/user_manager.py` L18, L99; launcher-category
  apps only). **The Start Menu watcher (plan Phase 2.3) is mandatory**: sync
  those files into `/usr/local/share/applications`.

## 5. Waydroid (docs.waydro.id + waydroid/waydroid @ e7d73e7, 2026-07-24)

- **Install (Ubuntu/Debian):**
  ```bash
  sudo apt install curl ca-certificates -y
  curl -s https://repo.waydro.id | sudo bash        # explicit codename: `| sudo bash -s -- <codename>`
  sudo apt update && sudo apt install waydroid -y
  ```
  Debian 14+/Ubuntu 26.10+ have waydroid in official repos; Debian 13 via
  backports.
- **`waydroid init`** flags: `[-i IMAGES_PATH] [-f] [-c SYSTEM_CHANNEL]
  [-v VENDOR_CHANNEL] [-r ROM_TYPE] [-s SYSTEM_TYPE]`;
  `-s` ∈ {VANILLA (default), FOSS, GAPPS}; OTA default
  `https://ota.waydro.id/system|/vendor`; downloads extract to
  `/var/lib/waydroid/images`.
- **Preseeding:** init checks `preinstalled_images_paths =
  ["/etc/waydroid-extra/images", "/usr/share/waydroid-extra/images"]`
  (`/etc` first). If `system.img` + `vendor.img` exist there, init sets
  `system_ota = "None"` and skips downloads
  (`tools/config/__init__.py` L37-40, `tools/actions/initializer.py` L57-69).
- **init REQUIRES binder**: `setup_config()` calls `setupBinderNodes()`
  before the preinstalled-images check and raises `OSError` if binder nodes
  can't be created (`tools/helpers/drivers.py` L120-146). **So `waydroid
  init` cannot run in the rootfs build chroot** — build places images in
  `/etc/waydroid-extra/images`; first boot (on our kernel) runs init.
  Ashmem is probed but not required. No flag exists to skip the binder
  check; hand-writing waydroid.cfg to bypass init is UNVERIFIED/undocumented.
- **Config/props files:** `/var/lib/waydroid/waydroid.cfg` (init-written;
  `[waydroid]` section: arch, vendor_type, binder nodes, images_path,
  system_ota…). `/var/lib/waydroid/waydroid_base.prop` is **regenerated by
  init/upgrade** — direct edits are lost then. Supported override: a
  `[properties]` section in waydroid.cfg is merged whenever props are
  regenerated (`tools/helpers/lxc.py` L360-366). Prefer `[properties]` over
  editing waydroid_base.prop.
- **Rendering selection** (`tools/helpers/lxc.py` L268-289): GPU path
  `ro.hardware.gralloc=gbm` + `ro.hardware.egl=mesa`; software fallback
  `ro.hardware.gralloc=default` + `ro.hardware.egl=swiftshader` (+
  `debug.stagefright.ccodec=0`). These keys are source-verified but NOT on
  the current docs site.
- **Props CLI:** `waydroid prop set <property> <value>`; unset with `""`;
  most need a session restart. `persist.waydroid.multi_windows` (bool)
  "Enables/Disables window integration with the desktop"
  (docs.waydro.id/usage/waydroid-prop-options).
- **Apps:** `waydroid app install xyz.apk` / `app list` /
  `app launch <package>` (also `remove`, `intent`).
- **Shared folders** (docs.waydro.id/faq/setting-up-a-shared-folder):
  `sudo mount --bind <src> ~/.local/share/waydroid/data/media/0/<target>`;
  documented targets: `Documents`, `Download`, `Music`, `Pictures`,
  `Movies`. Reverse: `sudo bindfs --mirror=$(id -u)
  ~/.local/share/waydroid/data/media/0 /mnt/waydroid`.
- **Networking:** bridge `waydroid0`, 192.168.240.1/24, DHCP
  .2–.254, dnsmasq `--strict-order --bind-interfaces` on ports 53/67;
  nftables table `inet lxc` or iptables INPUT 53/67 + FORWARD accept +
  MASQUERADE (`data/scripts/waydroid-net.sh`, run on container start).
  Troubleshooting (docs): firewalld trusted zone for waydroid0; ufw allow
  53/67 + default allow FORWARD; `iptables -P FORWARD ACCEPT`.
- **Session model:** root side `waydroid container
  {start,stop,restart,freeze,unfreeze}` (systemd unit
  `waydroid-container.service`, `BusName=id.waydro.Container`,
  `WantedBy=multi-user.target`); user side `waydroid session {start,stop}`,
  `show-full-ui`, `app *`, `prop *`. Per-user data at
  `$XDG_DATA_HOME/waydroid` (`~/.local/share/waydroid`).
- **Kernel requirements** (docs debugging page): binder + (ashmem OR
  memfd); check `zgrep -i -e android -e memfd -e ashmem /proc/config.gz`.
  Binder device name sets accepted include `binder`/`hwbinder`/`vndbinder`
  (plus anbox-* and puddlejumper aliases). PSI warning fix: kernel cmdline
  `psi=1`.

## 6. Prior art — Waydroid inside WSL2

### ddcash/WayDroid-Windows (PowerShell installer; all verified from clone)

- Installs into an existing apt distro; official repo script; skips init if
  `/var/lib/waydroid/waydroid.cfg` exists; uses
  `waydroid --details-to-stdout init`.
- Kernel: `zcat /proc/config.gz > .config` + `scripts/config --set-val
  ANDROID_BINDER_IPC y --set-val ANDROID_BINDERFS y --set-str
  ANDROID_BINDER_DEVICES 'binder,hwbinder,vndbinder' --set-val
  ANDROID_BINDER_IPC_RUST n --set-val ANDROID_BINDER_ALLOC_KUNIT_TEST n`,
  `yes '' | make olddefconfig`, `make -j$(nproc) bzImage modules`,
  `make modules_install`. Binder self-test: mount binderfs on a temp dir,
  `ls`, unmount, `echo BINDER_OK`.
- **modprobe multi-module quirk:** modprobe treats extra args as module
  *parameters* — load one per call:
  ```bash
  for m in bridge iptable_filter iptable_nat iptable_mangle ip_tables xt_MASQUERADE xt_CHECKSUM; do
    modprobe "$m" 2>/dev/null
  done
  ```
- **WSLg black-window fix:** windows render black with `[WARN:COPY MODE]`
  title unless `/mnt/shared_memory` is mounted before WSLg's compositor
  starts. Fix in `/etc/wsl.conf`:
  ```ini
  [boot]
  systemd = true
  command = mkdir -p /mnt/shared_memory && mount -t tmpfs tmpfs /mnt/shared_memory
  ```
  Related race: Start Menu icon indexing can start WSLg before the boot
  hook — ddcash parks Waydroid's per-app `.desktop` files in
  `~/.local/share/applications-disabled/`.
- **Stuck 1×1 buffer:** Waydroid talking directly to WSLg's RDP-backed
  compositor renders a stuck 1×1 buffer, so ddcash nests a Weston
  (`weston --backend=wayland-backend.so`, then `WAYLAND_DISPLAY=wayland-1`
  for the session). Start order: modprobe loop → `waydroid container start`
  (root) → nested weston → `waydroid session start` → poll log for
  `is ready` (≤90 s) → `waydroid show-full-ui`.
- **Anti-freeze:** patches `hardware_manager.py` `suspend()` to add a
  `"none"` mode + `sed -i 's/^suspend_action = .*/suspend_action = none/'
  /var/lib/waydroid/waydroid.cfg`. Manual unfreeze:
  `lxc-unfreeze -P /var/lib/waydroid/lxc -n waydroid`.
  (The `suspend_action` cfg key is ddcash's patched addition — UNVERIFIED
  upstream; upstream freeze control is `waydroid container freeze/unfreeze`.)
- **Smoke test:** `wsl --shutdown`, start script, poll ≤40×3 s for
  `waydroid status` matching `Session:\s*RUNNING` AND
  `Container:\s*RUNNING`, then stop.
- **Uninstall:** progressive — shortcuts/launchers; `-RemoveWaydroid`: stop
  container, `apt-get remove -y waydroid`, `rm -rf /var/lib/waydroid`;
  `-RemoveKernel`: restore newest `.wslconfig.bak-*` or strip
  `kernel=`/`vmIdleTimeout=` lines, delete kernel dir, `wsl --shutdown`.
  Gap: does not revert `/etc/wsl.conf` (we must).
- Launchers use `wsl -d X -e bash -c "script.sh"` (the `-c` form) — plain
  direct-exec was less reliable at keeping `setsid`-detached processes alive.

### onomatopellan gist + sourhub226/waydroid-on-wsl2

- Ubuntu 25.04 (`.wsl` file from releases.ubuntu.com), Android 13 /
  LineageOS 20 image, kernel 6.6.y.
- Kernel config delta: only `CONFIG_ANDROID_BINDER_IPC=y` +
  `CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder"` on top of
  stock config-wsl (no BINDERFS — both variants proven; we ship BINDERFS=y
  like ddcash since waydroid prefers binderfs).
- Build per repo README; modules via `gen_modules_vhdx.sh` → `.wslconfig`
  `kernel=` + `kernelModules=`.
- Software rendering: `/var/lib/waydroid/waydroid_base.prop` ←
  `ro.hardware.gralloc=default`, `ro.hardware.egl=swiftshader`. NOTE:
  sourhub226 later *removed* this step (commits fba2267/47db2c7,
  2026-05-30) — stock (auto-detected) rendering apparently worked for them.
  Spike must test both.
- Start: `weston --backend=wayland-backend.so` (nested), inside it
  `waydroid session start`, wait for `Android with user 0 is ready`, then
  `waydroid show-full-ui`. Weston GPU assist: `export GALLIUM_DRIVER=d3d12`.
- **Mirrored networking conflict:** dnsmasq ports collide in mirrored mode.
  Workaround: `.wslconfig` `[experimental] ignoredPorts=53,67,68` — or just
  use NAT (our v1 stance, ADR-003).
- Kernel-series change (5.15→6.6, ashmem gone) requires
  `sudo waydroid upgrade --offline` or Waydroid won't boot.
- dbus weirdness on first run → `wsl.exe --shutdown` and retry.
- **Neither guide uses `persist.waydroid.multi_windows`** — per-app windows
  against WSLg is untested territory; the nested-Weston workaround implies
  the direct WSLg path is buggy. **Top spike question** (SPIKE.md Q1).

## 7. casualsnek/waydroid_script

- **Dormant:** last commit `d5289cf` 2026-01-05; zero releases/tags; 124
  open issues incl. #282 "abandoned?" (2026-08-26). Per plan → **pin to
  commit `d5289cf`** (manifest), keep fork option open. Top fork
  `ayasa520/waydroid_script` is effectively the co-maintainer's copy.
- Install/run:
  ```bash
  git clone https://github.com/casualsnek/waydroid_script
  cd waydroid_script && python3 -m venv venv
  venv/bin/pip install -r requirements.txt     # tqdm, requests, InquirerPy; system dep: lzip
  sudo venv/bin/python3 main.py install {libndk|libhoudini|magisk|gapps|microg|widevine|smartdock}
  sudo venv/bin/python3 main.py certified      # Android ID for Play "uncertified device" registration
  ```
  `-a/--android-version {11,13}` (default 13). Trap: README says
  `main.py google` — that subcommand doesn't exist; the real one is
  `certified`.
- CPU mapping (their README/help): libndk "better for AMD",
  libhoudini (Intel's, from WSA 11 image) "better for Intel"; phrased as a
  performance observation, not a hard rule.
- Certification flow: reads `android_id` from the GSF database in the
  container, user registers it at google.com/android/uncertified, waits
  10–20 min, clears Play Services cache. Requires GApps installed + running.

## 8. WSA behaviour reference (MustardChef/WSABuilds, LTS since 2311)

What "good" felt like — the UX bar for Windroid: per-app Start Menu entries;
a Settings app (`wsa-settings://` URI) with app list, shutdown button, GPU
selection, networking toggles; shared-user-folder file handling ("Windows"
location inside Android's Files app; APK install from Files). Latest LTS
release 2026-01-04.

## UNVERIFIED items — status after Phase 0 (spike 2026-08-30, see SPIKE.md)

1. **CLOSED — works.** `persist.waydroid.multi_windows=true` direct against
   WSLg gives true per-app RAIL windows; 3 apps verified simultaneously; no
   stuck-1×1 buffer on WSLg 1.0.73.2. Nested Weston not needed.
2. **NOT NEEDED so far.** `vmIdleTimeout=-1` was never set; sessions
   survived normally. Revisit only if the VM teardown bites.
3. **CLOSED — auto-detect is correct.** init itself picks
   `gralloc=default` + `egl=swiftshader` on WSL2 (no /dev/dri); it does NOT
   misfire on `/dev/dxg`. The forced-props override is redundant there.
4. **CLOSED.** WSL 2.7.8.0 on the spike machine (WSLg 1.0.73.2, stock
   kernel 6.18.33.1-1).
5. **PARTIAL.** Audio plumbing verified (AudioFlinger MIXER thread up;
   PulseServer protocol 35 answers). Audible out / mic / clipboard need an
   unlocked interactive desktop.
6. **CLOSED — ddcash's patch still required.** `suspend_action` is a real
   waydroid.cfg key in 1.6.x (`freeze` default) but upstream `suspend()`
   only recognizes `"stop"`; anything else — including `none` — freezes
   the container (`tools/services/hardware_manager.py` L21-26). Android's
   own screen-off timer triggers it, windows vanish, nothing unfreezes.
   Fix: rootfs/patch-waydroid.py adds the `none` branch (assert-guarded),
   firstboot sets `suspend_action = none`.

## New facts from Phase 0 (spike 2026-08-30)

- **`waydroid init` never early-returns**: `is_initialized()` (cfg file
  AND rootfs dir) only triggers a log line; init proceeds into
  `setup_config()` regardless (1.6.2 `actions/initializer.py` L125). The
  skip-if-cfg-exists behaviour is ddcash's installer, not upstream.
- **init writes an empty `[properties]` section** — appending another one
  breaks configparser (`DuplicateSectionError`). Grep before appending.
- **`waydroid app install/launch` must run as the session user** — root
  sees "session is stopped".
- **Downloads sharing on WSL needs two deviations from the docs.waydro.id
  mechanism** (plain `mount --bind` yields an empty dir inside Android):
  (1) WSL roots are `private` propagation — `mount --make-rshared /` first
  (native systemd hosts are rshared, which is why the documented way works
  there); (2) drvfs (9p, `trans=fd`) binds can't be read from the container
  namespace — interpose `bindfs -o allow_other --force-user=1023
  --force-group=1023 --create-for-user=1000 --create-for-group=1000`.
  Verified: `/storage/emulated/0/Download` lists the Windows files.
- **WSLg Start Menu pipeline**: app list is enumerated at RDP connect, not
  live — new `.desktop` entries surface after the next session restart.
  WSLg converts `Icon=` PNGs to `.ico` under
  `%LOCALAPPDATA%\Temp\WSLDVCPlugin\<distro>\` and writes `.lnk` files to
  `%APPDATA%\...\Start Menu\Programs\<distro>\` targeting
  `C:\Program Files\WSL\wslg.exe -d <distro> --cd ~ -- <Exec>`.
- **Waydroid marks stock (preinstalled) apps `NoDisplay=true`** — only
  user-installed apps get Start Menu entries. Desired.
- **`[WARN:COPY MODE]`** = WSLg shared-memory fast path off; content still
  renders via the copy path. Fresh `wsl --shutdown` + boot (tmpfs in
  [boot] command) restores the fast path; in-place session restarts can
  regress to copy mode. Perf item, not correctness.
- **RAIL window titles come from the Android app's label** (Jelly ⇒
  "Browser") — don't match windows by package name.
- Spike timings (i9-13980HX/NVMe): cold start 17.1 s, warm launch 2.5 s.
