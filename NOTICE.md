# Third-party notices

The MIT license in [`LICENSE`](LICENSE) covers the Windroid glue in this
repository: the kernel config fragment, rootfs build scripts, installer,
setup wizard, tray app, CLI and docs.

Windroid **builds upon and bundles** third-party software, none of which is
relicensed here. Each remains under its own terms:

| Component | Licence | Role |
|---|---|---|
| Linux kernel — [microsoft/WSL2-Linux-Kernel](https://github.com/microsoft/WSL2-Linux-Kernel) | GPL-2.0 | The binder-enabled kernel is Microsoft's config plus three Android options (`kernel/windroid.fragment`) |
| [Waydroid](https://github.com/waydroid/waydroid) | GPL-3.0 | Runs the Android container. Patched at image-build time by `rootfs/patch-waydroid.py` (see that file for the change and why) |
| Android system images (LineageOS / AOSP), fetched from `ota.waydro.id` | Apache-2.0 plus the licences of their components | The Android OS itself |
| Weston / WSLg | MIT | Per-app windows, Start Menu entries, clipboard, audio |
| Ubuntu base rootfs and its packages | per-package (mostly GPL / MIT / BSD) | Host environment for Waydroid |
| [Aurora Store](https://gitlab.com/AuroraOSS/AuroraStore) | GPL-3.0 | Bundled app store, shipped unmodified from F-Droid |
| [Fennec (Firefox for Android)](https://github.com/mozilla/gecko-dev) | MPL-2.0 | Bundled browser, shipped unmodified from F-Droid |
| [Material Files](https://github.com/zhanghai/MaterialFiles) | GPL-3.0 | Bundled file manager, shipped unmodified from F-Droid |
| [Inno Setup](https://jrsoftware.org/isinfo.php) | modified BSD-style | Build-time toolchain for the setup wizard (not redistributed in this repo) |

Bundled APKs are downloaded during the image build from F-Droid's signed
index and verified against the SHA-256 hashes it publishes; the exact
versions and hashes shipped in a release are pinned in
[`manifest/versions.json`](manifest/versions.json).

## Google Apps

**GApps images are never redistributed by this project.** The public
artifacts ship the VANILLA (Google-free) Android image. The `-Gapps`
installer flag fetches Google's image on the user's own machine at install
time. See [`docs/DECISIONS.md`](docs/DECISIONS.md) ADR-004.
