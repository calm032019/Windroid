# Phase 0 spike runbook — Waydroid in WSL2, end to end

**Status: NOT YET EXECUTED.** This runbook must run on a real Windows 11
machine (~2–3 days). Every command below is sourced from
`docs/UPSTREAM-FACTS.md` (verified 2026-08-30) — if a step behaves
differently, record it here and update UPSTREAM-FACTS, don't improvise
silently. Phase 1–2 automation is generated from this file, so record
**exact** commands, outputs, and fixes, including dead ends.

Machine log (fill in): CPU ___ · RAM ___ · GPU ___ · Windows build ___ ·
WSL version (`wsl --version`) ___ · Date ___

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

- [ ] F-Droid runs in its own desktop window
- [ ] Start Menu entry exists for it (note what glue was needed)
- [ ] Clipboard + audio work
- [ ] Every fix recorded above with exact commands and keys
- [ ] Q1–Q4 answered; UNVERIFIED items 1/2/3/5/6 in UPSTREAM-FACTS closed

## Findings log (append as you go — include dead ends)

| # | Symptom | Root cause | Exact fix | Feeds |
|---|---|---|---|---|
| — | | | | |
