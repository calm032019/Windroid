# Performance log

All numbers come from `scripts/bench.ps1` — never hand-timed. Record the
machine, manifest version, and raw output for every row. Budgets are for the
NVMe reference machine.

## Budgets

| Metric | Budget | How measured (bench.ps1 stage) |
|---|---|---|
| Cold start: nothing running → app window visible | ≤ 20 s | `cold-start` |
| Warm app launch | ≤ 3 s | `warm-launch` |
| Idle RAM with session up, no apps | ≤ 1.5 GB after reclaim | `idle-ram` (after 5 min settle) |
| Install time (100 Mbit, excl. reboot) | ≤ 5 min | not a bench.ps1 stage — timed by `install.ps1 -Bench` (writes `bench-install.txt` in the install root) |

## Baselines (Phase 1 artifacts, before any tuning)

| Date | Manifest | Machine | Cold start | Warm launch | Idle RAM | Install | Notes |
|---|---|---|---|---|---|---|---|
| 2026-08-30 | spike (pre-manifest) | i9-13980HX, 32 GB, NVMe | **17.1 s** ✅ | **2.5 s** ✅ | ~5.3 GB pre-reclaim (after-settle TBD) | n/a (manual spike) | Hand-assembled stack (SPIKE.md F13), stopwatch = window-visible poll; memory cap 8 GB, autoMemoryReclaim=gradual |
| 2026-08-30 | 0.1.0 (zip, local artifacts) | i9-13980HX, 32 GB, NVMe | — | — | — | **63 s** ✅ (excl. download; +~2 min for the 1.37 GB zip at 100 Mbit) | Full clean install from Windroid.zip: import + firstboot (preseeded, no downloads) + smoke test incl. 3 bundled-app installs |

## Tuning log

One row per change; keep failed experiments — they're the record that stops
someone retrying them.

| Date | Change | Metric affected | Before → After | Kept? |
|---|---|---|---|---|
| — | — | — | — | — |

## Graphics ladder status (Phase 3)

- **(a) Software rendering baseline:** committed. Measured smoothness at
  1080p window sizes: *TBD*.
- **(b) Hardware GL/Vulkan via /dev/dxg + Mesa d3d12 in the Android image:**
  R&D timebox opens: *TBD*, closes 2 weeks later. Survey of existing
  Waydroid+WSL2 GPU issues/PRs goes here before any code.
- **(c) Go/no-go decision:** *TBD* — recorded here and in DECISIONS.md.
