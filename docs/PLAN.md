# Windroid — Android Subsystem for Windows

**Build plan.** Written 2026-08-30. Execute phases in order; do not start a phase until the previous phase's exit criteria pass. Versions and flags drift — verify against upstream docs at build time.

## Working agreements (read first, apply throughout)

1. **Never invent paths, flags, prop keys, or config names.** If a value isn't confirmed by upstream docs/source or by testing on the machine, stop and check. Sources of truth are listed in §3.
2. **Verify before building.** Waydroid image versions, WSL kernel tags, and the maintenance status of third-party scripts change. Check them at the start of each phase.
3. **User surface stays minimal**: one installer command, one tray icon, one CLI. All complexity lives in the build system.
4. **Harvest, don't rediscover.** Several people have already fought these bugs (§3 prior art). Read their fixes before debugging anything yourself.
5. When blocked or when a step's behaviour contradicts this plan, report it and ask — don't guess.

## 1. Goal and non-goals

**Goal:** Android apps running in individual resizable windows on the Windows 11 desktop, launchable from the Start Menu, installed via one command in under 5 minutes, reliable enough for daily use.

**Non-goals for v1** (record as backlog, do not build):
- Gaming performance parity with BlueStacks (they have years of GPU work; we ship apps, not games)
- Windows 10 support
- Camera passthrough
- Apps behind Play Integrity hard enforcement (modern banking apps) or DRM above Widevine L3
- Windows-on-ARM (interesting later — native ARM images need no translation layer)

## 2. Architecture decision

Rebuilding WSA proper means a hypervisor integration, a custom Android fork, and a graphics virtualisation stack — the thing Microsoft built with a large team and still killed (end of support 5 March 2025; removed from the Store). Not the project.

**Chosen architecture: Waydroid (LXC-based Android container) running inside WSL2, displayed and integrated through WSLg.**

| WSA capability | Provided by | Our work |
|---|---|---|
| Lightweight VM, fast boot, dynamic memory | WSL2 (Hyper-V utility VM) | None |
| Per-app desktop windows, taskbar presence | WSLg (Wayland → RDP/RAIL) | Verify + glue |
| Start Menu shortcuts | WSLg auto-generates from `.desktop` files | Watcher to ensure entries exist per Android app |
| Clipboard, audio out/in | WSLg | Verify |
| GPU plumbing | WSLg `/dev/dxg` (partial — see Phase 3) | R&D |
| Android runtime | Waydroid (LineageOS-based; Android 13 confirmed working on WSL2 by prior art) | Packaging |
| Binder kernel support | **Missing from stock WSL2 kernel** | **We build this** |
| ARM-only app support | libndk (AMD) / libhoudini (Intel) via waydroid_script | Integration |
| Installer / lifecycle / updates | Nothing | **We build this** |

Build-vs-buy: we build exactly four things — the kernel config, the prebaked distro image, the installer, and the Windows tray/integration layer. Everything else is upstream.

**Rejected alternatives** (documented so nobody relitigates): see `docs/DECISIONS.md`.

## 3. Sources of truth and prior art

Read these before writing code; harvest their fixes:

- `microsoft/WSL2-Linux-Kernel` — base kernel; build from the tag matching the installed WSL kernel version
- `waydroid/waydroid` + docs.waydro.id — install docs, kernel requirements, networking debugging pages
- `ddcash/WayDroid-Windows` — an existing PowerShell installer for exactly this stack. Study its fix list: kernel tag matching, modprobe multi-module quirk, the WSLg black-window bug (`/mnt/shared_memory` must be mounted before the compositor starts), uninstall/revert flow
- `onomatopellan`'s Waydroid-in-WSL2 gist + `sourhub226/waydroid-on-wsl2` — Android 13 on WSL2 with sound; documents the software-rendering props, mirrored-networking conflict, and the ashmem removal in 6.6.x kernels
- `casualsnek/waydroid_script` — libndk/libhoudini, Magisk, GApps certification helper. **Check maintenance status; fork and pin if stale**
- `microsoft/wslg` — architecture docs (how RAIL windowing and audio actually work)
- `MustardChef/WSABuilds` — behaviour reference for what "good" felt like in WSA (shortcuts, settings app, file handling)

Harvested findings live in `docs/UPSTREAM-FACTS.md`; anything marked UNVERIFIED there must be confirmed on a real machine before it is treated as truth.

## 4. Repo layout (monorepo)

```
windroid/
  kernel/          # config fragment + build script; CI builds bzImage per WSL tag
  rootfs/          # scripted build of the importable distro tar (vanilla + gapps flavours)
  installer/       # install.ps1, uninstall.ps1; later a winget manifest
  windows/         # tray app (stage 1: PowerShell; stage 2: Tauri or WinUI 3)
  scripts/         # bench.ps1 measurement harness, dev helpers, windroid CLI
  manifest/        # version manifest pinning every artifact
  .github/workflows/
  docs/            # SPIKE.md, PERF.md, DECISIONS.md, known-limits.md
```

## Phase 0 — Spike (manual, one dev machine, ~2–3 days)

Prove the stack end to end before automating anything. Document every failure and exact fix in `docs/SPIKE.md` — Phase 1–2 automation is built from this file.

1. Windows 11 host, virtualisation enabled. `wsl --install --no-distribution`, then install Ubuntu (current LTS or newer — prior art used 25.04 successfully).
2. Enable systemd in `/etc/wsl.conf`.
3. Build the custom kernel:
   - Clone `microsoft/WSL2-Linux-Kernel` **at the tag matching `uname -r`** in the running distro.
   - Start from Microsoft's own config (`Microsoft/config-wsl`) — the kernel is global to all WSL2 distros (Risk R1), so it must be a strict superset.
   - Enable: `CONFIG_ANDROID_BINDER_IPC=y`, `CONFIG_ANDROID_BINDERFS=y`, `CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder"`. Note: ashmem no longer exists in 6.6.x-series kernels — current Waydroid handles this via memfd; do not chase ashmem patches.
   - Build; install via `.wslconfig` `kernel=` path **or** the newer WSL Settings app (Developer → custom kernel/modules). Record which mechanism the installed WSL version supports.
   - `wsl --shutdown`, confirm `uname -r` shows the custom kernel and `/dev/binderfs` or binder devices appear.
4. Install Waydroid from the official repo; `sudo waydroid init` (VANILLA image first).
5. Start container + session; `waydroid show-full-ui`. Known first-run issues from prior art: dbus errors → `wsl --shutdown` and retry; black WSLg window → the `/mnt/shared_memory` mount-ordering fix from ddcash's repo.
6. If rendering fails, force software rendering in `/var/lib/waydroid/waydroid_base.prop`: `ro.hardware.gralloc=default` and `ro.hardware.egl=swiftshader` (confirm exact current keys against Waydroid docs — do not guess variants).
7. Networking: default NAT mode. Mirrored networking conflicts with Waydroid's dnsmasq port bindings — if mirrored mode is needed later, apply the documented workaround; for now, record NAT as the supported mode.
8. Enable per-app windows: `waydroid prop set persist.waydroid.multi_windows true`, restart session.
9. Install F-Droid via `waydroid app install`; launch it from its own window; test clipboard both directions, audio out, mic.

**Exit criteria:** F-Droid runs in its own desktop window; an entry for it exists in the Start Menu (via WSLg `.desktop` propagation — if not automatic, note what's missing); clipboard and audio work; `docs/SPIKE.md` contains every fix with exact commands and prop keys used.

## Phase 1 — Reproducible artifacts (CI)

Nothing from the spike survives as manual steps. Everything becomes a built, versioned artifact.

1. **kernel/**: GitHub Actions workflow. Input: WSL kernel tag. Output: bzImage (+ modules if needed) as a release artifact with its config attached. Scheduled job checks for new upstream WSL kernel tags and opens a PR/build.
2. **rootfs/**: script that produces an importable tar (`wsl --import`, or a `.wsl` distro file if the installed WSL version supports it):
   - Minimal Debian/Ubuntu, systemd enabled, Waydroid installed.
   - **Preseed the Android images** into `/var/lib/waydroid` at image-build time so first boot needs no download. Expected route: run `waydroid init` during rootfs build (init fetches/places images and shouldn't need binder — verify; if it does, place image files + config manually and document the layout).
   - Two flavours: `vanilla` (public artifact) and `gapps` (**never publicly redistributed** — licensing; built user-side by the installer with a flag).
   - First-boot systemd service brings up the Waydroid container + session and applies the SPIKE.md prop fixes.
3. **Version manifest**: one JSON pinning kernel build, rootfs build, Waydroid version, and image checksums. Every artifact traces to a manifest entry.

**Exit criteria:** on a clean Windows 11 VM, manually importing the artifacts (no scripts yet) reaches the Android home screen with zero interactive Linux-side steps.

## Phase 2 — Installer and Windows integration

1. **installer/install.ps1** — single command, idempotent, resumable across the WSL-install reboot:
   - Preflight: Windows 11 build, virtualisation enabled, disk space, existing WSL/distro detection.
   - Install or update WSL if needed.
   - **Merge, never clobber, `.wslconfig`** — other distros and Docker Desktop share it. Set: custom kernel path, memory cap (default `min(8GB, 50% of RAM)`), `autoMemoryReclaim=gradual`.
   - `wsl --import` the distro from the release artifact; run first-boot; health check; report PASS/FAIL like ddcash's smoke test (start session, wait for RUNNING, stop).
   - `-Gapps` flag triggers user-side gapps image build/fetch.
   - Target: **≤ 5 minutes** on a 100 Mbit connection, excluding the one possible reboot.
2. **windows/ tray app.** Stage 1 is PowerShell + toast notifications — do not build a GUI framework app until the PowerShell version has run for two weeks. Functions: status, start/stop/restart session, "Install APK…" file picker → `waydroid app install`, open Android settings, open logs, check for updates (reads GitHub releases against the local manifest, offers kernel/rootfs update).
3. **Start Menu**: confirm Waydroid-installed apps yield `.desktop` entries that WSLg lifts into the Start Menu (grouped under the distro). If coverage has gaps, add a small watcher in the distro that generates `.desktop` files from `waydroid app list`.
4. **`windroid` CLI**: `windroid install <apk>`, `windroid start|stop|status`, `windroid adb` (toggles ADB and prints the `adb connect` address).
5. **File sharing**: Windows → Android via bind-mounting the user's Downloads into the container's media path at session start. Take the exact mount mechanism from Waydroid docs/source — do not guess mountpoints.
6. **uninstall.ps1**: `wsl --unregister`, revert only our `.wslconfig` lines, remove shortcuts and tray app. A clean machine after uninstall is an exit criterion, not a nice-to-have.

**Exit criteria:** fresh machine → one command (+ possible reboot) → working Android with Start Menu entries; uninstaller returns the machine to its prior state including stock kernel; Docker Desktop on the same machine still works throughout.

## Phase 3 — Performance and graphics

Build `scripts/bench.ps1` first; record all numbers in `docs/PERF.md`. Budgets (NVMe reference machine):

| Metric | Budget |
|---|---|
| Cold start: nothing running → app window visible | ≤ 20 s |
| Warm app launch | ≤ 3 s |
| Idle RAM with session up, no apps | ≤ 1.5 GB after reclaim |
| Install time | ≤ 5 min |

1. Baselines from Phase 1 artifacts before any tuning.
2. Quick wins: sparse VHD, memory reclaim settings, disable unneeded Android services in the image, evaluate in-guest zram.
3. **Graphics ladder** — this is the make-or-break item, so it is explicitly de-risked:
   - **(a) Committed baseline: software rendering** (SwiftShader via the props from Phase 0). Ship-quality for productivity apps. Measure honestly: is the UI smooth at 1080p window sizes?
   - **(b) Timeboxed R&D — 2 weeks max:** hardware GL/Vulkan inside the container via WSLg's `/dev/dxg`. Realistic route requires Mesa's d3d12 gallium driver inside the Android image, i.e. a custom Waydroid image build. Before attempting: collect every open/closed Waydroid+WSL2 GPU issue and PR; pursue only the most-proven path found.
   - **(c) Go/no-go:** if (b) isn't stable at the timebox, ship (a) and file GPU as v2. **(b) must never block release.**
4. ARM-only apps: waydroid_script → libndk on AMD hosts, libhoudini on Intel; verified per-CPU in the test matrix.

## Phase 4 — Compatibility and polish

- GApps flavour: surface Google's "uncertified device" registration walkthrough in the tray app; document microG as the lighter alternative.
- Magisk optional via waydroid_script. Set expectations in docs: Play Integrity hard-enforced apps will fail regardless; Widevine L3 max. This is a documented limit, not a bug.
- Locale/timezone sync from Windows into the container; DPI sanity checks at 125–200% scaling.
- Update path proven end to end: old rootfs → new rootfs preserves user data (verify Waydroid's `/data` semantics across image swaps before shipping the updater).
- Stretch (backlog unless trivial): Android notifications → Windows toasts (NotificationListenerService app → local socket → toast); camera via v4l2loopback + a Windows capture bridge.

## Test matrix (minimum before v1)

- Windows 11: 23H2, 24H2, current release
- Intel and AMD CPUs (translation layers differ)
- 8 GB and 16/32 GB RAM machines
- iGPU-only and dGPU machines
- **Coexistence machine**: Docker Desktop + one other WSL distro already installed — the custom kernel and `.wslconfig` merge must not break them
- App set: F-Droid, a browser, a mainstream messenger, one ARM-only APK, one video app (codec/audio path), one mid-weight game (to document limits honestly in `known-limits.md`)

## Risk register

| # | Risk | Mitigation |
|---|---|---|
| R1 | `.wslconfig` kernel is **global to every WSL2 distro** on the machine | Kernel config is Microsoft's config + Android additions only; coexistence test in matrix; uninstaller reverts to stock |
| R2 | GPU acceleration doesn't land | Software rendering is the committed baseline; GPU is timeboxed R&D, never release-blocking |
| R3 | Upstream drift: WSL kernel changes (e.g. ashmem removal at 6.6.x), Waydroid changes, waydroid_script goes stale | Version manifest pins everything; CI canary builds against new WSL tags; fork stale scripts |
| R4 | Play Integrity / DRM app failures | Documented limit, surfaced in tray app; never promised |
| R5 | GApps redistribution licensing | Public artifacts are vanilla-only; gapps built user-side |
| R6 | Mirrored WSL networking conflicts with Waydroid's dnsmasq | NAT is the supported mode for v1; documented workaround noted for later |
| R7 | Low-spec machines (8 GB, SATA/HDD) | Honest published minimum spec; memory caps + reclaim on by default |

## Milestones

M0 spike proven → M1 CI artifacts boot on a clean VM → M2 one-command install/uninstall clean → M3 budgets met across matrix → M4 polish → **v1**.
