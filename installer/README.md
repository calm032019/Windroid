# installer/ — the one-command user surface

```powershell
# vanilla:
powershell -ExecutionPolicy Bypass -File install.ps1
# with Google apps (image is fetched on YOUR machine — never redistributed):
powershell -ExecutionPolicy Bypass -File install.ps1 -Gapps
# uninstall (returns the machine to its prior state, stock kernel included):
powershell -ExecutionPolicy Bypass -File uninstall.ps1
```

Design constraints (plan Phase 2.1/2.6):

- **Idempotent + resumable**: stages are tracked in
  `%LOCALAPPDATA%\Windroid\state.json`; if the WSL install forces a reboot,
  rerunning the same command continues from where it stopped.
- **`.wslconfig` is merged, never clobbered** — Docker Desktop and other
  distros share it. Every key we set is recorded with its previous value,
  and `uninstall.ps1` reverts exactly those lines (unit-tested in
  `tests/test-wslconfig-merge.ps1`; a timestamped backup is also written).
  Keys we set: `[wsl2] kernel / kernelModules / memory` (default
  `min(8GB, 50% RAM)`), `[experimental] autoMemoryReclaim=gradual /
  sparseVhd=true`. We warn on `networkingMode=mirrored` but never change it
  (ADR-003).
- **Health check**: after first boot the installer runs the ddcash-style
  smoke test (session start → poll for `Session: RUNNING` + `Container:
  RUNNING` → stop) and reports PASS/FAIL.
- Target: ≤ 5 minutes on 100 Mbit excluding the one possible reboot —
  measured with `-Bench` (feeds docs/PERF.md).

`-ArtifactSource` accepts a local directory (Phase 1 testing on a clean VM)
or a release download base URL. Artifact names and checksums come from the
release's `versions.json` manifest.

Not yet built (backlog): winget manifest.
