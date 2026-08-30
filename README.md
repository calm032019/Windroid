# Windroid — Android Subsystem for Windows

Android apps in individual resizable windows on the Windows 11 desktop,
launchable from the Start Menu, installed with one command. A community
replacement for the retired Windows Subsystem for Android (WSA), built from
upstream parts:

- **WSL2** provides the lightweight utility VM;
- **WSLg** provides per-app windows, Start Menu shortcuts, clipboard, audio;
- **Waydroid** provides the Android (LineageOS-based) container;
- **Windroid** provides the four missing pieces: a binder-enabled WSL2
  kernel, a prebaked distro image, a one-command installer, and the Windows
  tray/CLI integration layer.

Full rationale and the phase-by-phase plan: [`docs/PLAN.md`](docs/PLAN.md).
Decisions and rejected alternatives: [`docs/DECISIONS.md`](docs/DECISIONS.md).
What deliberately doesn't work: [`docs/known-limits.md`](docs/known-limits.md).

> **Status: pre-release scaffolding.** Phase 0 (manual spike on a real
> Windows 11 machine) has not been executed yet — see
> [`docs/SPIKE.md`](docs/SPIKE.md) for the runbook. Nothing here is
> installable by end users yet.

## Repo layout

| Path | Contents |
|---|---|
| `kernel/` | WSL2 kernel config fragment + build script; CI builds a bzImage per upstream WSL tag |
| `rootfs/` | Scripted build of the importable distro tar (vanilla flavour public; gapps built user-side) |
| `installer/` | `install.ps1` / `uninstall.ps1` — the one-command user surface |
| `windows/` | Tray app (stage 1: PowerShell + toasts) |
| `scripts/` | `windroid` CLI, `bench.ps1` measurement harness, dev helpers |
| `manifest/` | Version manifest pinning every artifact (kernel, rootfs, Waydroid images) |
| `docs/` | PLAN, SPIKE runbook, DECISIONS, PERF, known-limits, harvested upstream facts |
| `.github/workflows/` | Kernel + rootfs CI, upstream-tag canary |

## For developers

Start with `docs/PLAN.md` — the working agreements at the top are binding,
especially: **never invent paths, flags, prop keys, or config names**.
Verified upstream values live in `docs/UPSTREAM-FACTS.md` with sources;
anything marked UNVERIFIED there must be confirmed on a real machine before
automation depends on it.

Milestones: M0 spike proven → M1 CI artifacts boot on a clean VM → M2
one-command install/uninstall clean → M3 perf budgets met across the test
matrix → M4 polish → v1.
