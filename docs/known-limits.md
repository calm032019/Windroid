# Known limits

Honest, documented limits of Windroid v1. These are **not bugs**; the tray
app and README surface them so users aren't surprised. Update this file from
real test-matrix results, not guesses.

## Won't work, by design

- **Play Integrity hard-enforced apps** (most modern banking apps, Google
  Wallet tap-to-pay). Waydroid is an uncertified virtual device; Magisk and
  the certification helper get you *basic* attestation at best, and Google
  ratchets enforcement over time. Never promised.
- **DRM above Widevine L3.** Netflix & co. run at SD/L3 quality at best;
  some refuse to play entirely.
- **Camera passthrough.** Not in v1 (backlog: v4l2loopback + Windows capture
  bridge).
- **Windows 10.** WSLg requires Windows 11; we do not test or support 10.
- **Gaming parity with BlueStacks.** Software rendering is the v1 baseline
  (see ADR-002). Productivity apps are the target; document per-game results
  in the table below rather than promising anything.

## Degraded / caveated

- **Graphics: software rendering (SwiftShader).** Smooth for productivity
  UI at 1080p-ish window sizes; heavy games and 60 fps video may drop
  frames. Hardware GPU is Phase 3 R&D.
- **ARM-only apps** need a translation layer (libndk on AMD, libhoudini on
  Intel) installed via `waydroid_script`; per-app compatibility varies.
  Record per-CPU results in the test-matrix table.
- **Custom WSL2 kernel is global** to every WSL2 distro on the machine. Our
  kernel is Microsoft's own config plus binder additions only, and the
  coexistence test (Docker Desktop + another distro) gates every release —
  but users should know the kernel is shared.
- **Mirrored WSL networking** is unsupported in v1 (conflicts with
  Waydroid's dnsmasq). NAT only; preflight warns if mirrored mode is set.
- **8 GB machines**: usable with the default memory cap and reclaim, but
  expect slower cold starts and app evictions. Published minimum spec lives
  in the README.

## Per-app results (fill from test matrix — no entry, no claim)

| App | Arch | Result | Notes | Tested on |
|---|---|---|---|---|
| F-Droid | universal | — | | |
| (browser TBD) | | — | | |
| (messenger TBD) | | — | | |
| (ARM-only app TBD) | arm64 | — | | |
| (video app TBD) | | — | | |
| (mid-weight game TBD) | | — | | |
