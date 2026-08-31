#!/usr/bin/env python3
"""Preseed Waydroid Android images for the rootfs build.

`waydroid init` cannot run at image-build time (it hard-requires binder
nodes — docs/UPSTREAM-FACTS.md §5), so this reimplements exactly the
download half of waydroid's tools/helpers/images.py + the channel-URL
construction from tools/actions/initializer.py (verified against upstream
@ e7d73e7 and against the live OTA server on 2026-08-30):

  system: <channel>/<rom_type>/waydroid_<arch>/<system_type>.json
  vendor: <channel>/waydroid_<arch>/MAINLINE.json
  JSON:   {"response": [{"datetime": int, "url", "filename", "id": sha256-of-zip}, ...]}

Newest build = first entry with datetime greater than any stored one (the
server returns newest-first; we take response[0] like a fresh init would).
Zips are sha256-verified against 'id' and extracted (system.img/vendor.img)
into the target dir — /etc/waydroid-extra/images inside the rootfs, which
init checks FIRST and then skips all downloads (sets system_ota=None).

Usage:
  preseed-images.py --dest <rootfs>/etc/waydroid-extra/images \
      [--system-type VANILLA] [--arch x86_64] [--rom-type lineage] \
      [--manifest-out preseed-manifest.json]
"""
import argparse
import hashlib
import json
import os
import sys
import tempfile
import urllib.request
import zipfile

OTA_BASE_SYSTEM = "https://ota.waydro.id/system"
OTA_BASE_VENDOR = "https://ota.waydro.id/vendor"


def fetch_json(url):
    with urllib.request.urlopen(url, timeout=60) as r:
        if r.status != 200:
            raise RuntimeError(f"OTA channel {url} returned {r.status}")
        return json.load(r)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def download_and_extract(build, dest):
    url, filename, want_sha = build["url"], build["filename"], build["id"]
    with tempfile.NamedTemporaryFile(suffix=".zip", delete=False) as tmp:
        tmp_path = tmp.name
    try:
        print(f"  downloading {filename} ...", flush=True)
        urllib.request.urlretrieve(url, tmp_path)
        got = sha256_file(tmp_path)
        if got != want_sha:
            raise RuntimeError(
                f"sha256 mismatch for {filename}: expected {want_sha}, got {got}")
        print(f"  sha256 OK ({want_sha[:16]}…), extracting to {dest}", flush=True)
        with zipfile.ZipFile(tmp_path) as z:
            z.extractall(dest)
    finally:
        os.unlink(tmp_path)


def newest(channel_url):
    responses = fetch_json(channel_url)["response"]
    if not responses:
        raise RuntimeError(f"no builds on channel {channel_url}")
    return max(responses, key=lambda b: b["datetime"])


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--dest", required=True,
                   help="target images dir (…/etc/waydroid-extra/images)")
    p.add_argument("--system-type", default="VANILLA",
                   choices=["VANILLA", "FOSS", "GAPPS"])
    p.add_argument("--arch", default="x86_64")
    p.add_argument("--rom-type", default="lineage")
    p.add_argument("--manifest-out", default=None,
                   help="write a JSON record of what was preseeded")
    args = p.parse_args()

    system_ota = f"{OTA_BASE_SYSTEM}/{args.rom_type}/waydroid_{args.arch}/{args.system_type}.json"
    vendor_ota = f"{OTA_BASE_VENDOR}/waydroid_{args.arch}/MAINLINE.json"

    os.makedirs(args.dest, exist_ok=True)
    record = {"system_ota": system_ota, "vendor_ota": vendor_ota}
    for kind, channel in (("system", system_ota), ("vendor", vendor_ota)):
        build = newest(channel)
        print(f"{kind}: {build['filename']} (datetime {build['datetime']})")
        download_and_extract(build, args.dest)
        record[kind] = {k: build[k] for k in ("filename", "datetime", "id", "url")}

    for img in ("system.img", "vendor.img"):
        path = os.path.join(args.dest, img)
        if not os.path.isfile(path):
            print(f"ERROR: {img} missing after extraction — OTA zip layout "
                  f"changed, re-verify against upstream images.py", file=sys.stderr)
            return 1
        record.setdefault("images", {})[img] = {
            "sha256": sha256_file(path), "bytes": os.path.getsize(path)}

    # Marker so windroid-firstboot can tell what flavour was preseeded (a
    # gapps rootfs preseeds GAPPS images that init should use directly, not
    # park and re-download).
    with open(os.path.join(args.dest, ".system-type"), "w") as f:
        f.write(args.system_type + "\n")

    if args.manifest_out:
        with open(args.manifest_out, "w") as f:
            json.dump(record, f, indent=2)
        print(f"wrote {args.manifest_out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
