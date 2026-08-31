#!/usr/bin/env bash
# Generate assets/windroid.ico + windroid-256.png from assets/windroid.svg
# and copy the .ico into the rootfs files tree (used by
# /etc/wsl-distribution.conf [shortcut] icon and the Windows tray).
# Needs: librsvg2-bin (rsvg-convert), python3-pil.
set -euo pipefail
ASSETS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../assets" && pwd)"
ROOTFS_ICON_DIR="$ASSETS/../rootfs/files/usr/lib/windroid"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
for s in 16 24 32 48 64 128 256; do
    rsvg-convert -w "$s" -h "$s" "$ASSETS/windroid.svg" -o "$tmp/windroid-$s.png"
done
cp "$tmp/windroid-256.png" "$ASSETS/windroid-256.png"

python3 - "$tmp" "$ASSETS/windroid.ico" <<'PYEOF'
import sys
from PIL import Image
tmp, out = sys.argv[1], sys.argv[2]
sizes = [16, 24, 32, 48, 64, 128, 256]
imgs = [Image.open(f"{tmp}/windroid-{s}.png") for s in sizes]
# PIL writes every size from the largest source; append_images keeps the
# hand-rendered small rasters instead of naive downscales.
imgs[-1].save(out, format="ICO", sizes=[(s, s) for s in sizes],
              append_images=imgs[:-1])
PYEOF

mkdir -p "$ROOTFS_ICON_DIR"
cp "$ASSETS/windroid.ico" "$ROOTFS_ICON_DIR/windroid.ico"
echo "wrote $ASSETS/windroid.ico, $ASSETS/windroid-256.png, $ROOTFS_ICON_DIR/windroid.ico"
