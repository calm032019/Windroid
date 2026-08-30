# Architecture decision records

Decisions are recorded so nobody relitigates them. To reverse one, add a new
entry superseding it — don't edit history.

---

## ADR-001 — Waydroid inside WSL2, displayed through WSLg

**Date:** 2026-08-30 · **Status:** Accepted

**Context.** Microsoft killed WSA (end of support 5 March 2025; removed from
the Store). We want Android apps in individual resizable windows on the
Windows 11 desktop, Start Menu launchable, one-command install.

**Decision.** Waydroid (LXC-based Android container, LineageOS-derived)
running inside a WSL2 distro, displayed and integrated through WSLg
(Wayland → RDP/RAIL). We build exactly four things: the kernel config, the
prebaked distro image, the installer, and the Windows tray/integration layer.
Everything else is upstream.

**Consequences.** We depend on a custom WSL2 kernel (binder support), which
is global to every WSL2 distro on the machine (Risk R1). WSLg gives us
per-app windows, Start Menu shortcuts, clipboard, and audio for free — but
GPU acceleration inside the Android container is unsolved (Risk R2, Phase 3
timebox).

### Rejected alternatives

**Repackaged WSA (WSABuilds / MagiskOnWSA forks).** Works today in ~2 hours,
but the platform is dead — no security updates, compatibility rots as Android
API levels advance. Use only as a UX benchmark (see `docs/known-limits.md`
and the behavior notes in `docs/UPSTREAM-FACTS.md`).

**Custom Hyper-V/QEMU VM running Bliss OS.** Full control, but you must
build seamless per-app windowing yourself — months of work WSLg already
does. Only revisit if WSL is unavailable on target machines.

**Rebuilding WSA proper.** Hypervisor integration + custom Android fork +
graphics virtualisation stack — the thing Microsoft built with a large team
and still killed. Not the project.

---

## ADR-002 — Software rendering is the committed graphics baseline

**Date:** 2026-08-30 · **Status:** Accepted

SwiftShader software rendering (props recorded in SPIKE.md/UPSTREAM-FACTS.md)
is the ship-quality baseline for v1. Hardware GL/Vulkan via WSLg's
`/dev/dxg` + Mesa d3d12 inside the Android image is a **timeboxed 2-week
R&D item** in Phase 3 and must never block release. Go/no-go recorded in
`docs/PERF.md` when the timebox closes.

---

## ADR-003 — NAT is the supported WSL networking mode for v1

**Date:** 2026-08-30 · **Status:** Accepted

Mirrored networking (`networkingMode=mirrored`) conflicts with Waydroid's
dnsmasq port bindings (prior art, Risk R6). The installer does not set a
networking mode; if the user's `.wslconfig` already selects mirrored mode,
preflight warns and points at the documented workaround rather than silently
changing their config.

---

## ADR-004 — Vanilla images only in public artifacts

**Date:** 2026-08-30 · **Status:** Accepted

GApps images are never publicly redistributed (licensing, Risk R5). The
public rootfs artifact ships the VANILLA Waydroid system image; the `-Gapps`
installer flag performs the GAPPS image fetch/`waydroid init` **on the
user's machine**.

---

## ADR-005 — Tray app stage 1 is PowerShell, not a GUI framework

**Date:** 2026-08-30 · **Status:** Accepted

Stage 1 is PowerShell + toast notifications. A Tauri/WinUI 3 app is only
started after the PowerShell version has run for two weeks in real use.
Keeps the installer dependency-free and the iteration loop fast.
