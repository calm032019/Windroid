# Windroid — Android Subsystem for Windows

<p align="center"><img src="assets/windroid-256.png" width="128" alt="Windroid"></p>

> ### Ye Olde Descriptioun
>
> **Herken well, gentle reader**, and learn what manner of engine this be.
>
> Once did the House of Microsoft grant unto folk a wondrous thing, whereby
> the small applications of the Droid might dwell upon the Windowed
> desktop; but in the year of our Lord 2025, on the fifth day of March,
> they did strike it down and cast it out from their Store, and the people
> were left wanting. **Windroid** is the answer of the commons to that
> unkindness.
>
> The working of it is thus. Within thy machine there is builded a small
> and thrifty chamber (a *Subsystem for Linux*, as the learned name it),
> and within that chamber is set a true Android of the Lineage, penned
> like an honest beast in its stall by the keeper called *Waydroid*. Yet
> the beast is not seen in its stall; for a cunning glass named *WSLg*
> taketh each application by its own likeness and casteth it forth upon
> thy desktop as **its own window**, which thou mayest drag, stretch,
> minish and close as any Christian program. Their names are writ into thy
> Start Menu, all gathered in one coffer marked *Windroid*, and whatsoever
> new app thou dost install shall place itself there also, unbidden.
>
> Know moreover that the common kernel of the machine hath no knowledge of
> *binder*, that strange tongue in which all Androids speak unto
> themselves. Therefore have we forged a kernel anew, with that tongue
> granted unto it, and it is laid down beside the others without harm to
> any. And lest thou be left with an empty chamber, there ride within the
> installer a **market-stall** (Aurora), a **browser** (Fennec of the
> Firefox), a **keeper of files**, and the **Settings** of the Droid
> itself, that thou want for nothing on the first day.
>
> Two roads lead in: a **Setup of the wizardly sort**, which first
> examineth thy machine and telleth thee plainly whether it be wise to
> proceed and whether a restarting shall be required; or a **zipped
> coffer**, for they that prefer the older ways. Either road may be
> retraced, for the uninstaller putteth all things back as they were.
>
> *Here endeth the olde descriptioun; what followeth is plain moderne
> speech.*

Android apps in individual resizable windows on the Windows 11 desktop,
launchable from the Start Menu, installed with one command. A community
replacement for the retired Windows Subsystem for Android (WSA). Comes
preloaded with Aurora Store (Google Play catalogue, anonymous sign-in),
Fennec (Firefox), Material Files and Android Settings — all in one
**Start Menu → Windroid** folder, where every app you install also lands.

## Install

Grab either from the [latest release](../../releases/latest) — same
installer engine underneath, pick your style:

| Option | How |
|---|---|
| **`Windroid-Setup-<ver>.exe`** (recommended) | Double-click. A setup wizard checks your system first and tells you up front whether a restart will be needed (only if WSL was never enabled). Adds an entry to *Add/Remove Programs* for clean uninstall. |
| **`Windroid.zip`** | Unzip anywhere, double-click `INSTALL.cmd`. Same checks in console form; remove later with `UNINSTALL.cmd`. |

Requirements: Windows 11 (x86-64), virtualization enabled in firmware,
~15 GB free disk, 8 GB RAM minimum. If a restart is requested (first-time
WSL enablement), reboot and run the installer again — it resumes where it
left off. Nothing is downloaded during install; everything ships inside.

## What it's built from

- **WSL2** provides the lightweight utility VM;
- **WSLg** provides per-app windows, Start Menu shortcuts, clipboard, audio;
- **Waydroid** provides the Android (LineageOS-based) container;
- **Windroid** provides the four missing pieces: a binder-enabled WSL2
  kernel, a prebaked distro image, a one-command installer, and the Windows
  tray/CLI integration layer.

Full rationale and the phase-by-phase plan: [`docs/PLAN.md`](docs/PLAN.md).
Decisions and rejected alternatives: [`docs/DECISIONS.md`](docs/DECISIONS.md).
What deliberately doesn't work: [`docs/known-limits.md`](docs/known-limits.md).

> **Status: Phase 0 spike PROVEN (2026-08-30).** Android 13 (LineageOS 20)
> runs in per-app resizable windows on a real Windows 11 machine: custom
> binder kernel ✅, multi-window direct to WSLg ✅, Start Menu entries ✅,
> Windows→Android Downloads sharing ✅, cold start 17.1 s ✅. See
> [`docs/SPIKE.md`](docs/SPIKE.md) for the findings log. CI artifacts and
> the one-command installer (Phases 1–2) are written but not yet exercised
> end-to-end — nothing is installable by end users yet.

## Repo layout

| Path | Contents |
|---|---|
| `kernel/` | WSL2 kernel config fragment + build script; CI builds a bzImage per upstream WSL tag |
| `rootfs/` | Scripted build of the importable distro tar (vanilla flavour public; gapps built user-side) |
| `installer/` | `install.ps1` / `uninstall.ps1` (the engine) + `windroid-setup.iss` (Inno Setup wizard — build with `scripts/make-setup.ps1`). Two distribution formats share the engine: `Windroid-Setup-<ver>.exe` (wizard, system-check page, Add/Remove Programs entry) and `Windroid.zip` (`INSTALL.cmd`, built by `scripts/make-dist.ps1`) |
| `windows/` | Tray app (stage 1: PowerShell + toasts) |
| `scripts/` | `windroid` CLI, `bench.ps1` measurement harness, `make-dist.ps1` zip packager, dev helpers |
| `assets/` | Windroid logo (SVG master; `.ico`/`.png` generated by `scripts/make-icons.sh`) |
| `manifest/` | Version manifest pinning every artifact (kernel, rootfs, Waydroid images) |
| `docs/` | PLAN, SPIKE runbook, DECISIONS, PERF, known-limits, harvested upstream facts |
| `.github/workflows/` | Kernel + rootfs CI, upstream-tag canary, release assembly, lint/test CI |

## Minimum spec

Windows 11 (build 22000+) with virtualisation enabled, x86-64 CPU, **8 GB
RAM** (16 GB recommended), ~15 GB free disk, WSL ≥ 2.4.4. SSD strongly
recommended — see `docs/known-limits.md` for what 8 GB/HDD machines can
expect. Windows 10 and Windows-on-ARM are not supported in v1.

## For developers

Start with `docs/PLAN.md` — the working agreements at the top are binding,
especially: **never invent paths, flags, prop keys, or config names**.
Verified upstream values live in `docs/UPSTREAM-FACTS.md` with sources;
anything marked UNVERIFIED there must be confirmed on a real machine before
automation depends on it.

Milestones: M0 spike proven → M1 CI artifacts boot on a clean VM → M2
one-command install/uninstall clean → M3 perf budgets met across the test
matrix → M4 polish → v1.
