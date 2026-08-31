#!/usr/bin/env python3
# Compose the release versions.json from built artifacts (mirrors what
# release.yml does in CI, for a local dist build).
import glob, hashlib, json, sys

dist, kdir, out = sys.argv[1], sys.argv[2], sys.argv[3]

def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()

build = json.load(open(glob.glob(dist + "/*.build.json")[0]))
preseed = json.load(open(glob.glob(dist + "/*.preseed.json")[0]))
apks = json.load(open(glob.glob(dist + "/*.apks.json")[0]))
rootfs_tar = glob.glob(dist + "/windroid-rootfs-vanilla-*.tar.gz")[0]
bz = glob.glob(kdir + "/bzImage-windroid-*")[0]
tag = bz.split("bzImage-windroid-")[1]

m = {
  "$schema": "./versions.schema.json",
  "manifest_version": "0.1.0",
  "released": "2026-08-30",
  "channel": "dev",
  "kernel": {
    "wsl_kernel_tag": tag,
    "artifact": "bzImage-windroid-" + tag,
    "sha256": sha(bz),
    "modules_artifact": "modules-windroid-" + tag + ".vhdx",
    "modules_sha256": sha(glob.glob(kdir + "/modules-windroid-*.vhdx")[0]),
    "config_fragment": "kernel/windroid.fragment"
  },
  "rootfs": {
    "build_id": build["build_id"],
    "base": build["base"],
    "flavours": {
      "vanilla": {"artifact": rootfs_tar.split("/")[-1], "sha256": sha(rootfs_tar), "public": True},
      "gapps": {"artifact": None, "sha256": None, "public": False,
                "note": "Never redistributed (ADR-004). Built user-side by install.ps1 -Gapps."}
    }
  },
  "waydroid": {
    "version": build["waydroid_version"],
    "android_version": "13 (LineageOS 20)",
    "system_image_sha256": preseed["images"]["system.img"]["sha256"],
    "vendor_image_sha256": preseed["images"]["vendor.img"]["sha256"]
  },
  "preinstalled_apps": apks,
  "waydroid_script": {
    "repo": "https://github.com/casualsnek/waydroid_script",
    "commit": "d5289cf",
    "note": "Pinned per Risk R3. Doc trap: real subcommand is certified, not google."
  },
  "installer": {"min_windows_build": 22000, "min_wsl_version": "2.4.4"}
}
json.dump(m, open(out, "w"), indent=2)
print("wrote", out)
