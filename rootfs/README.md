# rootfs/ — the importable Windroid distro

Builds the WSL distro tar that the installer imports: minimal Ubuntu base +
systemd + Waydroid + **preseeded Android images** + the Windroid guest glue.
Phase 1 exit criterion: importing this on a clean machine reaches the
Android home screen with zero interactive Linux-side steps.

```bash
sudo rootfs/build.sh                     # vanilla (the public artifact)
sudo rootfs/build.sh --flavour gapps     # LOCAL ONLY — never published (ADR-004)
```

## How preseeding works (the binder constraint)

`waydroid init` hard-requires binder nodes, so it cannot run in the build
chroot. Instead, `preseed-images.py` reimplements exactly the download half
of waydroid's own `tools/helpers/images.py` (same OTA channels, sha256
check, zip extraction) and places `system.img`/`vendor.img` into
`/etc/waydroid-extra/images` — the first path init checks; when found, init
skips all downloads (`system_ota=None`). The real `waydroid init` then runs
at **first boot** on the user's binder-enabled kernel via
`windroid-firstboot.service`. See docs/UPSTREAM-FACTS.md §5.

GApps: the published artifact preseeds VANILLA only. With `-Gapps`, the
installer flips `GAPPS=true` in `/etc/windroid/windroid.conf`; first boot
then parks the preseeded vanilla images and runs `waydroid init -s GAPPS`,
downloading the GApps image on the user's machine.

## Guest layout (files/)

| Path | Role |
|---|---|
| `etc/wsl.conf` | systemd on + `/mnt/shared_memory` tmpfs before WSLg (black-window fix) |
| `etc/wsl-distribution.conf` | `.wsl`-file metadata (OOBE user, shortcut) |
| `etc/windroid/windroid.conf` | toggles: GAPPS, FORCE_SOFTWARE_RENDERING, MULTI_WINDOWS, NESTED_WESTON, WINDOWS_DOWNLOADS |
| `usr/local/bin/windroid-firstboot` | oneshot: binder check → rendering/multi-window props via waydroid.cfg `[properties]` → `waydroid init` |
| `usr/local/bin/windroid-session` | user-side start/stop/status/ensure; polls for session readiness |
| `usr/local/bin/windroid-app` | `.desktop` Exec target: boots stack if needed, then `waydroid app launch` |
| `usr/local/bin/windroid-desktop-sync` | mirrors `~/.local/share/applications/waydroid.*.desktop` → `/usr/local/share/applications` (WSLg doesn't scan the user dir) |
| `usr/local/sbin/windroid-prep` | the only sudo surface: tmpfs, net modules (one modprobe per module), container start/stop, Downloads bind mount |
| `etc/systemd/system/…` | firstboot oneshot + desktop-sync path watcher |
| `etc/sudoers.d/windroid` | NOPASSWD for windroid-prep verbs only |

## Verification points for Phase 0/1 (not yet machine-tested)

- `waydroid.cfg` `[properties]` written *before* first init: confirm init's
  config save preserves the section (upstream merges `[properties]` when
  regenerating props; round-trip preservation is assumed, not yet proven).
- `persist.waydroid.multi_windows` honored from `[properties]` (vs. needing
  `waydroid prop set` at runtime) — spike Q1.
- Chroot install of the waydroid deb: postinst behavior in a chroot
  (service enablement is done explicitly here in case postinst skipped it).
