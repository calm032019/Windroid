#!/usr/bin/env python3
"""Preseed the bundled app suite for the rootfs build (plan: user lands
with a store, a browser and a file manager ready to use).

Downloads from F-Droid's official repo, driven by index-v1.jar (the
signed index; we verify each APK's sha256 against the index hash):

  com.aurora.store            Aurora Store (Play Store client, anonymous)
  org.mozilla.fennec_fdroid   Fennec (Firefox for Android, F-Droid build)
  me.zhanghai.android.files   Material Files (file manager)

APK choice per package: highest versionCode whose nativecode list is
absent (pure Java/Kotlin) or contains x86_64 — the Waydroid image is
x86_64 and has no ARM translation layer by default.

APKs land in <dest> as <package>.apk; windroid-session installs them on
the first session (one-time, stamped). All three are FOSS and
redistributable (GPLv3 / MPL / GPLv3) — unlike GApps (ADR-004).

Usage:
  preseed-apks.py --dest <rootfs>/etc/windroid/apks \
      [--manifest-out apks-manifest.json]
"""
import argparse
import hashlib
import json
import os
import sys
import tempfile
import urllib.request
import zipfile

REPO = "https://f-droid.org/repo"
PACKAGES = [
    "com.aurora.store",
    "org.mozilla.fennec_fdroid",
    "me.zhanghai.android.files",
]


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def fetch_index():
    print("fetching F-Droid index-v1.jar ...", flush=True)
    with tempfile.NamedTemporaryFile(suffix=".jar", delete=False) as tmp:
        tmp_path = tmp.name
    try:
        urllib.request.urlretrieve(f"{REPO}/index-v1.jar", tmp_path)
        with zipfile.ZipFile(tmp_path) as z:
            with z.open("index-v1.json") as f:
                return json.load(f)
    finally:
        os.unlink(tmp_path)


def pick_apk(index, pkg):
    apks = index["packages"].get(pkg)
    if not apks:
        raise RuntimeError(f"{pkg} not in F-Droid index")
    ok = [a for a in apks
          if "nativecode" not in a or "x86_64" in a["nativecode"]]
    if not ok:
        raise RuntimeError(f"{pkg}: no x86_64-compatible APK in index")
    return max(ok, key=lambda a: a["versionCode"])


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--dest", required=True)
    p.add_argument("--manifest-out", default=None)
    args = p.parse_args()

    os.makedirs(args.dest, exist_ok=True)
    index = fetch_index()
    record = {}
    for pkg in PACKAGES:
        apk = pick_apk(index, pkg)
        url = f"{REPO}/{apk['apkName']}"
        out = os.path.join(args.dest, f"{pkg}.apk")
        print(f"{pkg}: {apk['apkName']} (versionCode {apk['versionCode']})",
              flush=True)
        urllib.request.urlretrieve(url, out)
        got = sha256_file(out)
        if got != apk["hash"]:
            print(f"ERROR: sha256 mismatch for {pkg}: index {apk['hash']}, "
                  f"got {got}", file=sys.stderr)
            return 1
        record[pkg] = {"apkName": apk["apkName"],
                       "versionCode": apk["versionCode"],
                       "versionName": apk.get("versionName"),
                       "sha256": got}

    if args.manifest_out:
        with open(args.manifest_out, "w") as f:
            json.dump(record, f, indent=2)
        print(f"wrote {args.manifest_out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
