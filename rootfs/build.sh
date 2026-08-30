#!/usr/bin/env bash
# Build the importable Windroid distro tar (plan Phase 1.2).
#
# Usage (needs root — chroot + ownership-preserving tar):
#   sudo rootfs/build.sh [--flavour vanilla|gapps] [--base-release noble] [--out DIR]
#
# Output: windroid-rootfs-<flavour>-<build_id>.tar.gz (+ .wsl copy and
# preseed/build manifests) suitable for `wsl --import` and, with the
# embedded /etc/wsl-distribution.conf, for `wsl --install --from-file`.
#
# The gapps flavour exists for LOCAL/user-side builds only and must never be
# published (ADR-004). CI builds vanilla only.
#
# Everything in here is scripted from docs/SPIKE.md-verified facts and
# docs/UPSTREAM-FACTS.md — no interactive Linux-side steps may survive
# (Phase 1 exit criterion).
set -euo pipefail

FLAVOUR=vanilla
BASE_RELEASE=noble          # Ubuntu 24.04 LTS; waydroid repo supports it (UPSTREAM-FACTS §5)
OUT_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --flavour) FLAVOUR="$2"; shift 2 ;;
        --base-release) BASE_RELEASE="$2"; shift 2 ;;
        --out) OUT_DIR="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done
[[ "$FLAVOUR" == "vanilla" || "$FLAVOUR" == "gapps" ]] || { echo "flavour must be vanilla|gapps" >&2; exit 2; }
[[ $EUID -eq 0 ]] || { echo "run as root (chroot + tar ownership)" >&2; exit 2; }

BUILD_ID="$(date -u +%Y%m%d%H%M)"
OUT_DIR="${OUT_DIR:-$SCRIPT_DIR/out}"
WORK="$SCRIPT_DIR/work/$FLAVOUR-$BUILD_ID"
ROOT="$WORK/rootfs"
mkdir -p "$OUT_DIR" "$ROOT"

echo "==> Fetching Ubuntu base ($BASE_RELEASE)"
# ubuntu-base is the minimal official rootfs tarball (no kernel — correct
# for WSL, whose kernel comes from the host side).
BASE_INDEX_URL="https://cdimage.ubuntu.com/ubuntu-base/releases/$BASE_RELEASE/release"
BASE_TARBALL="$(curl -fsSL "$BASE_INDEX_URL/" | grep -oE 'ubuntu-base-[0-9.]+-base-amd64\.tar\.gz' | sort -uV | tail -n1)"
[[ -n "$BASE_TARBALL" ]] || { echo "could not find ubuntu-base tarball at $BASE_INDEX_URL" >&2; exit 1; }
curl -fSL "$BASE_INDEX_URL/$BASE_TARBALL" -o "$WORK/$BASE_TARBALL"
tar -xzf "$WORK/$BASE_TARBALL" -C "$ROOT"

in_chroot() {
    chroot "$ROOT" /usr/bin/env \
        DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 PATH=/usr/sbin:/usr/bin:/sbin:/bin \
        bash -euo pipefail -c "$1"
}

echo "==> Preparing chroot"
# Non-recursive mounts only: an rbind of /sys drags in submounts that
# umount -R can't always release, and a still-mounted /sys then poisons the
# final tar (first CI run failed exactly that way).
mount -t proc proc "$ROOT/proc"
mount -t sysfs sysfs "$ROOT/sys"
mount --bind /dev "$ROOT/dev"
mount -t devpts devpts "$ROOT/dev/pts" 2>/dev/null || true
cp /etc/resolv.conf "$ROOT/etc/resolv.conf"
cleanup() {
    for m in "$ROOT/dev/pts" "$ROOT/dev" "$ROOT/sys" "$ROOT/proc"; do
        if mountpoint -q "$m"; then umount "$m" 2>/dev/null || umount -l "$m" || true; fi
    done
}
trap cleanup EXIT

echo "==> Installing packages"
in_chroot "apt-get update"
in_chroot "apt-get install -y --no-install-recommends \
    systemd systemd-sysv dbus sudo curl ca-certificates gnupg \
    kmod iproute2 python3"
# Official Waydroid repo setup; the script takes the codename as a
# POSITIONAL arg ($1) — the '-s' in the docs is bash's own stdin flag
# (verified from the script source; UPSTREAM-FACTS §5). Pass the release
# explicitly — inside a chroot the detection can't be trusted.
in_chroot "curl -s https://repo.waydro.id | bash -s -- $BASE_RELEASE"
in_chroot "apt-get update && apt-get install -y waydroid weston"
WAYDROID_VERSION="$(in_chroot "dpkg-query -W -f '\${Version}' waydroid")"

echo "==> Preseeding Android images (flavour: $FLAVOUR)"
# waydroid init can't run here (needs binder — UPSTREAM-FACTS §5); place
# images where init looks first: /etc/waydroid-extra/images. GAPPS images
# are preseeded only in local gapps builds, never in published artifacts.
SYSTEM_TYPE=VANILLA
[[ "$FLAVOUR" == "gapps" ]] && SYSTEM_TYPE=GAPPS
python3 "$SCRIPT_DIR/preseed-images.py" \
    --dest "$ROOT/etc/waydroid-extra/images" \
    --system-type "$SYSTEM_TYPE" \
    --manifest-out "$WORK/preseed-manifest.json"

echo "==> Installing Windroid guest files"
# files/ mirrors the target filesystem layout.
cp -a "$SCRIPT_DIR/files/." "$ROOT/"
chmod 0755 "$ROOT/usr/local/bin/windroid-firstboot" \
           "$ROOT/usr/local/bin/windroid-session" \
           "$ROOT/usr/local/bin/windroid-app" \
           "$ROOT/usr/local/bin/windroid-desktop-sync" \
           "$ROOT/usr/local/sbin/windroid-prep"
chmod 0440 "$ROOT/etc/sudoers.d/windroid"
chown root:root "$ROOT/etc/wsl-distribution.conf"
chmod 0644 "$ROOT/etc/wsl-distribution.conf"
[[ "$FLAVOUR" == "gapps" ]] && sed -i 's/^GAPPS=false/GAPPS=true/' "$ROOT/etc/windroid/windroid.conf"

echo "==> Creating default user + enabling units"
in_chroot "id windroid >/dev/null 2>&1 || useradd -m -u 1000 -s /bin/bash -G sudo windroid"
in_chroot "systemctl enable windroid-firstboot.service windroid-desktop-sync.path"
in_chroot "visudo -cf /etc/sudoers.d/windroid"

echo "==> Cleaning"
in_chroot "apt-get clean && rm -rf /var/lib/apt/lists/*"
# .wsl format rules: no /etc/resolv.conf, no shadow hashes in the archive
# (UPSTREAM-FACTS §3). WSL regenerates resolv.conf; windroid has no password.
rm -f "$ROOT/etc/resolv.conf"
sed -i 's/^windroid:[^:]*:/windroid:!:/' "$ROOT/etc/shadow"

cleanup
trap - EXIT
# Refuse to pack over live mounts — a leaked mount means host files in the tar.
if mount | grep -qF "$ROOT/"; then
    echo "ERROR: mounts still active under $ROOT:" >&2
    mount | grep -F "$ROOT/" >&2
    exit 1
fi

echo "==> Packing"
NAME="windroid-rootfs-$FLAVOUR-$BUILD_ID"
# proc/sys/dev/run must exist but ship empty (kernel/WSL populate them).
tar --numeric-owner -C "$ROOT" \
    --exclude='./proc/*' --exclude='./sys/*' --exclude='./dev/*' --exclude='./run/*' \
    -c . | gzip --best > "$OUT_DIR/$NAME.tar.gz"
cp "$OUT_DIR/$NAME.tar.gz" "$OUT_DIR/$NAME.wsl"
cp "$WORK/preseed-manifest.json" "$OUT_DIR/$NAME.preseed.json"
cat > "$OUT_DIR/$NAME.build.json" <<EOF
{
  "build_id": "$BUILD_ID",
  "flavour": "$FLAVOUR",
  "base": "ubuntu-base $BASE_RELEASE ($BASE_TARBALL)",
  "waydroid_version": "$WAYDROID_VERSION",
  "public": $( [[ "$FLAVOUR" == "vanilla" ]] && echo true || echo false )
}
EOF
( cd "$OUT_DIR" && sha256sum "$NAME.tar.gz" "$NAME.wsl" > "$NAME.SHA256SUMS" )

echo "==> Done:"
ls -lh "$OUT_DIR/$NAME"*
