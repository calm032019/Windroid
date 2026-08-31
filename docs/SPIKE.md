# Phase 0 spike runbook — Waydroid in WSL2, end to end

**Status: EXECUTED 2026-08-30** (this machine log + findings table below).
Every command below is sourced from `docs/UPSTREAM-FACTS.md` (verified
2026-08-30) — if a step behaves differently, record it here and update
UPSTREAM-FACTS, don't improvise silently. Phase 1–2 automation is generated
from this file, so record **exact** commands, outputs, and fixes,
including dead ends.

Machine log: CPU i9-13980HX (32 threads) · RAM 32 GB · GPU NVIDIA dGPU +
Intel iGPU · Windows 11 build 26200.9168 · WSL 2.7.8.0 (kernel 6.18.33.1-1,
WSLg 1.0.73.2) · Date 2026-08-30 · Distro Ubuntu-24.04 (noble) · Docker
Desktop installed (coexistence machine)

## The four questions this spike exists to answer

- **Q1 (make-or-break): does `persist.waydroid.multi_windows true` give
  per-app RAIL windows against WSLg directly?** No prior art tests this —
  both guides nest a Weston to dodge a stuck-1×1-buffer bug when Waydroid
  talks straight to WSLg's RDP compositor. Outcomes to test, in order:
  (a) multi_windows against WSLg directly; (b) multi_windows inside nested
  Weston (windows-within-a-window — fails the product goal but informative);
  (c) full-ui via nested Weston (prior-art fallback, single window).
  If only (c) works, the product needs a rethink at the windowing layer —
  stop and report per working agreement #5.
- **Q2: rendering** — does Waydroid's auto-detect work on WSL2 (sourhub226
  eventually dropped the SwiftShader props), or does it misfire on
  `/dev/dxg` and need the software-rendering override?
- **Q3: Start Menu** — Waydroid writes `.desktop` files to
  `~/.local/share/applications`, which WSLg does NOT scan. Verify a synced
  copy in `/usr/local/share/applications` yields a Start Menu entry, and
  that launching from it works when no session is up yet.
- **Q4: clipboard / audio out / mic** — implied by WSLg, never verified by
  prior art with Waydroid apps.

## 1. Host prep

```powershell
wsl --version          # record; .wsl-file features need >= 2.4.4
wsl --install --no-distribution   # if WSL absent; may require reboot
# Install Ubuntu (prior art used 25.04 via the .wsl file from releases.ubuntu.com)
wsl --install Ubuntu-25.04        # or double-click the downloaded .wsl
```

In the distro, enable systemd **and** the WSLg black-window fix in one go —
`/etc/wsl.conf`:

```ini
[boot]
systemd = true
command = mkdir -p /mnt/shared_memory && mount -t tmpfs tmpfs /mnt/shared_memory
```

(The tmpfs must be mounted before WSLg's compositor starts or Waydroid
windows render black with `[WARN:COPY MODE]` in the title — ddcash.)
Then `wsl --shutdown` and reopen.

- [ ] `systemctl is-system-running` returns running/degraded
- [ ] `mount | grep shared_memory` shows the tmpfs

## 2. Custom kernel

```bash
uname -r    # e.g. 6.6.87.2-microsoft-standard-WSL2 → tag linux-msft-wsl-6.6.87.2
sudo apt install -y build-essential flex bison dwarves libssl-dev libelf-dev cpio qemu-utils bc kmod rsync python3
git clone --depth 1 -b linux-msft-wsl-<ver> https://github.com/microsoft/WSL2-Linux-Kernel.git
cd WSL2-Linux-Kernel
# Windroid additions on top of Microsoft's own config (R1: strict superset):
./scripts/config --file Microsoft/config-wsl \
  --set-val CONFIG_ANDROID_BINDER_IPC y \
  --set-val CONFIG_ANDROID_BINDERFS y \
  --set-str CONFIG_ANDROID_BINDER_DEVICES "binder,hwbinder,vndbinder"
make olddefconfig KCONFIG_CONFIG=Microsoft/config-wsl   # non-interactive; no `yes` pipe (SIGPIPEs under pipefail)
make -j$(nproc) KCONFIG_CONFIG=Microsoft/config-wsl
make INSTALL_MOD_PATH="$PWD/modules" modules_install
sudo ./Microsoft/scripts/gen_modules_vhdx.sh "$PWD/modules" $(make -s kernelrelease) modules.vhdx
```

Copy `arch/x86/boot/bzImage` and `modules.vhdx` to e.g. `C:\Windroid\kernel\`,
then `.wslconfig` (`%USERPROFILE%\.wslconfig` — MERGE, don't clobber):

```ini
[wsl2]
kernel=C:\\Windroid\\kernel\\bzImage
kernelModules=C:\\Windroid\\kernel\\modules.vhdx
```

Record which mechanism you used: `.wslconfig` vs WSL Settings app
(Developer → custom kernel/modules) — and whether `vmIdleTimeout=-1` proved
necessary (UNVERIFIED item #2).

`wsl --shutdown`, reopen, then verify:

```bash
uname -r          # must show your kernelrelease (typically ends in + or your localversion)
sudo mkdir -p /dev/binderfs && sudo mount -t binder binder /dev/binderfs && ls /dev/binderfs && sudo umount /dev/binderfs && sudo rmdir /dev/binderfs && echo BINDER_OK
zgrep -i -e android -e memfd /proc/config.gz
```

- [ ] custom kernel booted  - [ ] BINDER_OK  - [ ] no other distro broke
      (if Docker Desktop is installed: does it still start?)

## 3. Waydroid install + init

```bash
sudo apt install -y curl ca-certificates
curl -s https://repo.waydro.id | sudo bash     # explicit codename: `| sudo bash -s -- <codename>` (positional arg)
sudo apt update && sudo apt install -y waydroid
sudo waydroid --details-to-stdout init         # VANILLA is the default
```

Record: Waydroid version, Android/LineageOS image version, download sizes,
time taken, where images landed (`/var/lib/waydroid/images` expected).
Known first-run issue: weird dbus errors → `wsl.exe --shutdown`, retry.

## 4. First boot (prior-art-proven path first)

```bash
# Networking modules — one modprobe per module (multi-arg = parameters, not modules):
for m in bridge iptable_filter iptable_nat iptable_mangle ip_tables xt_MASQUERADE xt_CHECKSUM; do sudo modprobe "$m"; done
sudo systemctl start waydroid-container.service    # or: sudo waydroid container start
```

**Path A — direct to WSLg (Q1a, try first):**

```bash
waydroid session start        # wait for "Android with user 0 is ready"
waydroid show-full-ui
```

Record exactly what renders: black window? `[WARN:COPY MODE]` title? stuck
1×1 buffer? working UI?

**Path B — nested Weston (prior-art fallback):**

```bash
sudo apt install -y weston
export WAYLAND_DISPLAY=wayland-0
weston --backend=wayland-backend.so --width=1280 --height=800 &
export WAYLAND_DISPLAY=wayland-1
waydroid session start        # wait for ready, then:
waydroid show-full-ui
```

- [ ] Android home screen reached (which path? ___)
- [ ] If rendering broken, apply software rendering and retest — put it in
      the supported override location, `[properties]` in
      `/var/lib/waydroid/waydroid.cfg` (waydroid_base.prop is regenerated
      by init/upgrade):
      ```ini
      [properties]
      ro.hardware.gralloc=default
      ro.hardware.egl=swiftshader
      ```
      then `sudo waydroid upgrade --offline` (regenerates props), restart
      container+session. Record Q2 answer.
- [ ] Network inside Android works (browser or `waydroid shell -- ping`);
      NAT mode only (mirrored → dnsmasq port conflict; `[experimental]
      ignoredPorts=53,67,68` is the documented workaround we're NOT using in v1)

## 5. Multi-window (Q1 proper)

```bash
waydroid prop set persist.waydroid.multi_windows true
waydroid session stop && waydroid session start
sudo waydroid app install /path/to/F-Droid.apk
waydroid app launch org.fdroid.fdroid
```

Record for each of Q1 (a)/(b)/(c): own taskbar entry? resizable? minimize/
restore? focus behaviour? screenshot into `docs/spike-assets/`.

## 6. Start Menu (Q3)

```bash
ls ~/.local/share/applications/waydroid.*.desktop   # written by session's user_manager
sudo cp ~/.local/share/applications/waydroid.org.fdroid.fdroid.desktop /usr/local/share/applications/
```

- [ ] Entry appears in Start Menu (under the distro group) — how long?
- [ ] Launching from Start Menu with WSL cold / session down: what happens?
      (This determines whether the launcher needs a wrapper that boots the
      session first.)

## 7. Clipboard, audio, mic (Q4)

- [ ] Copy text Windows → Android app and back
- [ ] Audio out (video in F-Droid-installed app or browser)
- [ ] Mic in (recorder app) — WSLg PulseAudio
- [ ] Idle behaviour: does the container freeze when the window unfocuses
      (ddcash's anti-freeze patch targeted this)? Record whether
      `waydroid container unfreeze` or his `suspend_action` patch is needed.

## 8. Teardown rehearsal (feeds uninstall.ps1)

```bash
waydroid session stop && sudo waydroid container stop
sudo apt remove -y waydroid && sudo rm -rf /var/lib/waydroid
```
Windows: remove our `.wslconfig` lines, `wsl --shutdown`, verify stock
kernel boots (`uname -r` without our localversion) and other distros still
work.

## Exit criteria (from PLAN.md)

- [x] F-Droid runs in its own desktop window (RAIL window `F-Droid
      (Ubuntu-24.04)`; 3 app windows verified coexisting: F-Droid,
      Settings, Browser)
- [x] Start Menu entry exists for it (glue needed: windroid-desktop-sync
      into /usr/local/share/applications + session restart — see F7)
- [~] Clipboard + audio: audio plumbing verified end to end (AudioFlinger
      mixer thread up; WSLg PulseServer reachable, protocol v35). Audible
      output, mic, and clipboard need a human at the unlocked desktop —
      the spike ran with the workstation locked (see F12).
- [x] Every fix recorded (findings log below)
- [x] Q1–Q4 answered; UNVERIFIED items 1/3/4/6 closed, 2 not needed so
      far, 5 partially (plumbing yes, ears/eyes pending)

## Q1–Q4 answers (2026-08-30)

- **Q1: YES — (a) works.** `persist.waydroid.multi_windows=true` against
  WSLg directly gives true per-app RAIL windows. Three apps verified
  simultaneously as separate desktop windows (each an msrdc top-level
  window + sub-surfaces). No stuck-1×1-buffer bug on WSLg 1.0.73.2. No
  nested Weston needed — NESTED_WESTON stays default-off.
- **Q2: auto-detect is correct on WSL2.** `waydroid init` itself chose
  `ro.hardware.gralloc=default` + `ro.hardware.egl=swiftshader` (no
  /dev/dri render node in WSL guests), plus `sys.use_memfd=true`. The
  FORCE_SOFTWARE_RENDERING override is redundant on WSL (harmless to keep
  as belt-and-braces; explains why sourhub226 dropped the props).
- **Q3: YES with glue.** Sync to /usr/local/share/applications works;
  WSLg lifts entries and even converts icons to .ico. Two caveats:
  (1) WSLg enumerates at RDP connect — new apps appear in the Start Menu
  after the next session restart, not live; (2) stock LineageOS apps have
  `NoDisplay=true` in their .desktop, so only user-installed apps surface
  (correct behaviour). Cold launch from the shortcut works: wslg.exe →
  windroid-app → boots container+session → window in 17.1 s.
- **Q4: plumbing verified, senses pending.** AudioFlinger has a live
  MIXER output thread; WSLg PulseServer answers from the distro. Clipboard
  and audible playback untestable with the workstation locked.

## Findings log (append as you go — include dead ends)

| # | Symptom | Root cause | Exact fix | Feeds |
|---|---|---|---|---|
| F1 | `wsl --install Ubuntu-24.04 --no-launch` then non-interactive root exec skips OOBE cleanly | — | `useradd -m -s /bin/bash -G sudo windroid` + `[user] default=windroid` in wsl.conf | installer |
| F2 | Kernel build: exact tag `linux-msft-wsl-6.18.33.1` existed; build.sh --from-uname resolved it; ~14 min on 32 threads; kernelrelease `6.18.33.1-microsoft-standard-WSL2-windroid+` | — | `.wslconfig` `kernel=`/`kernelModules=` (C:\\Windroid\\kernel\\); BINDER_OK on first boot; docker-desktop distro boots the same kernel fine (R1 pass) | kernel/, installer |
| F3 | `waydroid upgrade --offline` crashed: `DuplicateSectionError: section 'properties' already exists` | init writes an empty `[properties]` on save; appending a second one breaks configparser | Always grep for existing `[properties]` before appending (windroid-firstboot already does; ad-hoc appends must too) | rootfs |
| F4 | Audit claim "firstboot's early waydroid.cfg write defeats init" | FALSE for upstream: `is_initialized()` = cfg exists AND rootfs dir exists; and `init()` only LOGS "Already initialized", never returns early (waydroid 1.6.2 source) | No change needed; cfg-skip was ddcash's installer logic, not upstream's | rootfs |
| F5 | `sudo waydroid app install` → "WayDroid session is stopped" | Session state is per-user; root has no session | Run `waydroid app install/launch` as the session user (no sudo) | SPIKE §5, CLI |
| F6 | `[WARN:COPY MODE]` in window title on first session | WSLg shared-memory fast path not engaged (started WSLg before tmpfs in the boot sequence that first created it) | Full `wsl --shutdown` + fresh boot with `/mnt/shared_memory` tmpfs in wsl.conf [boot] → clean title. Recurs on in-place session restarts; content still renders (copy path), fresh boot restores fast path | PERF, tray |
| F7 | Synced .desktop entries didn't appear in Start Menu live | WSLg app-list plugin enumerates at RDP connect, not via inotify | Restart session (wsl --terminate + relaunch) → `.lnk` appears under Start Menu\Programs\<Distro>; entry correctly targets `wslg.exe … windroid-app <pkg>` with converted .ico | windows/, docs |
| F8 | Only F-Droid got a Start Menu entry, not the 12 stock apps | Waydroid writes `NoDisplay=true` into stock LineageOS apps' .desktop | Working as intended — user-installed apps only | docs |
| F9 | Downloads share: documented `mount --bind` gives an EMPTY dir inside Android | Two causes: (1) drvfs is 9p `trans=fd` — its transport fds can't be reused from the container namespace; (2) WSL root is `private` propagation (native systemd roots are `rshared`), so late mounts never reach Android's internal storage re-binds (vold binds /data/media without rbind) | `mount --make-rshared /` in wsl.conf [boot] + `bindfs -o allow_other --force-user=1023 --force-group=1023 --create-for-user=1000 --create-for-group=1000` instead of mount --bind → `/storage/emulated/0/Download` shows Windows files | rootfs (windroid-prep), installer |
| F10 | Container freezes on Android's own screen-off/suspend; all app windows vanish; nothing unfreezes it | `suspend_action` IS an upstream waydroid.cfg key (1.6.x) but only `"stop"` is recognized — every other value (incl. `none`) falls through to `container_manager.freeze()`. The cfg value alone does NOT disable freezing (initial F10 entry was wrong) | ddcash's patch is still required: rootfs/patch-waydroid.py adds an explicit `none` branch to hardware_manager.py `suspend()` (assert-guarded against upstream drift) + `suspend_action = none` in firstboot. Manual unfreeze: `lxc-unfreeze -P /var/lib/waydroid/lxc -n waydroid` | rootfs, UPSTREAM-FACTS #6 |
| F11 | Jelly browser window "missing" after launch | Its RAIL window is titled "Browser (Ubuntu-24.04)", not "Jelly" | Match windows by enumeration, not app name | bench.ps1 |
| F12 | PrintWindow/CopyFromScreen can't capture msrdc content (locked workstation; DirectComposition) | RAIL windows render via DComp; GDI capture returns black | On-screen verification needs an unlocked desktop; Android-side `waydroid shell -- screencap` proves the pipeline up to WSLg | bench.ps1, docs |
| F13 | Timings (i9-13980HX, NVMe, 32 GB): cold start (wsl down → F-Droid window) **17.1 s**; warm app launch (Clock) **2.5 s**; vmmem ~5.3 GB right after boot+apps (before reclaim settle) | — | Within budgets (≤20 s / ≤3 s); idle-RAM after-reclaim measurement pending a quiet interval | PERF.md |
| F14 | scripts/windroid.ps1 unparseable at runtime ("Missing closing '}'") though pwsh CI parse passes | .ps1 saved UTF-8 without BOM → Windows PowerShell 5.1 decodes as ANSI; em-dash's last byte 0x94 becomes a smart closing quote and ends the string early | UTF-8 BOM added to every .ps1; CI step added checking BOM presence (pwsh can't catch this) | ci.yml, all .ps1 |
| F15 | Installer's Downloads-path sed fails "unterminated 's' command" (twice, same char) | PowerShell native-argv quoting mangles embedded `\"` when invoking `wsl -e bash -c "...\"$var\"..."` — the expression truncates mid-flight | Zero-quote channel: value → base64 → WSLENV env var → `bash -c 'echo $VAR \| base64 -d > /etc/windroid/downloads-path'`; windroid-prep reads the raw file | installer, windroid-prep |
| F16 | Windroid container crashes at boot / binder "cannot find target node" kernel spam while the spike distro also runs Waydroid | All WSL2 distros share one kernel; two Waydroid stacks corrupt each other's binder state | **Only one Waydroid distro may run per machine.** Disable/uninstall other Waydroid installs (spike distro's service disabled). Documented in known-limits | known-limits, installer preflight (future) |
| F17 | Taskbar shows generic Tux for all Android windows; Start Menu tiles badge with Tux | (a) WSLg's rdprail-shell keys app-list entries by the LAST dot-component of the .desktop filename but looks windows up by their full dotted app_id (`waydroid.<pkg>`) — exact match only, so association can never succeed (weston-mirror app-list.c, source-verified); (b) badge = `WSL2_DEFAULT_APP_OVERLAY_ICON` env, default linux.png | (a) tray app watches for Waydroid RAIL windows and applies app-icon + Windroid-badge via WM_SETICON, sourcing WSLg's own converted .ico cache (%LOCALAPPDATA%\Temp\WSLDVCPlugin\<distro>); (b) `.wslgconfig` `[system-distro-env]` points `WSL2_DEFAULT_APP_ICON`/`_OVERLAY_ICON` at /mnt/wslg/distro/usr/lib/windroid/windroid-256.png — per-distro effect from a global file since the path only resolves in Windroid's instance | tray, installer, UPSTREAM-FACTS §4 |
