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
| Install time (100 Mbit, excl. reboot) | ≤ 5 min | `install` (timed by install.ps1 -Bench) |

## Baselines (Phase 1 artifacts, before any tuning)

| Date | Manifest | Machine | Cold start | Warm launch | Idle RAM | Install | Notes |
|---|---|---|---|---|---|---|---|
| — | — | — | — | — | — | — | fill from bench.ps1 output |

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
