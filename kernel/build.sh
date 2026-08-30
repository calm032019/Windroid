#!/usr/bin/env bash
# Build a binder-enabled WSL2 kernel from an upstream microsoft/WSL2-Linux-Kernel tag.
#
# Usage:
#   kernel/build.sh <linux-msft-wsl-TAG> [output-dir]
#   kernel/build.sh --from-uname [output-dir]   # resolve tag from the running WSL kernel
#
# Outputs into <output-dir> (default: kernel/out/<tag>/):
#   bzImage-windroid-<tag>       the kernel (.wslconfig [wsl2] kernel=)
#   modules-windroid-<tag>.vhdx  matching modules  (.wslconfig [wsl2] kernelModules=)
#   config-windroid-<tag>        full config actually built (attach to release)
#   SHA256SUMS
#
# Sources of truth: docs/UPSTREAM-FACTS.md §1 (build flow from the upstream
# README; tag-matching logic harvested from ddcash/WayDroid-Windows).
set -euo pipefail

REPO_URL="https://github.com/microsoft/WSL2-Linux-Kernel.git"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAGMENT="$SCRIPT_DIR/windroid.fragment"
LOCALVERSION_SUFFIX="-windroid"

die() { echo "ERROR: $*" >&2; exit 1; }

resolve_tag_from_uname() {
    # uname -r looks like 6.6.87.2-microsoft-standard-WSL2 (custom kernels
    # usually add '+'). Strip suffix, look for the exact upstream tag, else
    # fall back to the newest tag in the same major.minor (ddcash's logic).
    local krel kver tags exact
    krel="$(uname -r)"
    kver="${krel%%-*}"
    tags="$(git ls-remote --tags "$REPO_URL" 'linux-msft-wsl-*' \
        | sed -E 's#.*refs/tags/##; s/\^\{\}$//' | sort -uV)"
    exact="$(grep -Fx "linux-msft-wsl-$kver" <<<"$tags" || true)"
    if [[ -n "$exact" ]]; then
        echo "$exact"
        return
    fi
    local mm="${kver%.*.*}"   # 6.6.87.2 -> 6.6 ; 6.18.40.1 -> 6.18
    grep -E "^linux-msft-wsl-${mm//./\\.}\." <<<"$tags" | tail -n1 \
        || die "no upstream tag matches $krel (series $mm)"
}

TAG="${1:-}"
[[ -n "$TAG" ]] || die "usage: $0 <linux-msft-wsl-TAG>|--from-uname [output-dir]"
if [[ "$TAG" == "--from-uname" ]]; then
    TAG="$(resolve_tag_from_uname)"
    echo "Resolved tag from uname -r: $TAG"
fi
[[ "$TAG" == linux-msft-wsl-* ]] || die "tag must look like linux-msft-wsl-6.6.87.2, got: $TAG"

OUT_DIR="${2:-$SCRIPT_DIR/out/$TAG}"
SRC_DIR="$SCRIPT_DIR/WSL2-Linux-Kernel"
mkdir -p "$OUT_DIR"

echo "==> Fetching $TAG"
if [[ -d "$SRC_DIR/.git" ]]; then
    git -C "$SRC_DIR" fetch --depth 1 origin "tag" "$TAG"
    git -C "$SRC_DIR" checkout -f "$TAG"
else
    git clone --depth 1 --branch "$TAG" "$REPO_URL" "$SRC_DIR"
fi
cd "$SRC_DIR"

# Microsoft/config-wsl is a symlink to arch/x86/configs/config-wsl; a git
# clone resolves it, but verify rather than assume.
[[ -e Microsoft/config-wsl ]] || die "Microsoft/config-wsl missing — upstream layout changed, check docs/UPSTREAM-FACTS.md §1"

echo "==> Applying Windroid fragment on top of Microsoft's config"
cp Microsoft/config-wsl .config
# scripts/config edits keys in place; olddefconfig resolves new deps with
# defaults (same flow ddcash uses). Keep Microsoft's config untouched so the
# diff below is honest.
while IFS= read -r line; do
    [[ "$line" =~ ^CONFIG_([A-Z0-9_]+)=y$ ]] && ./scripts/config --enable "${BASH_REMATCH[1]}"
    [[ "$line" =~ ^CONFIG_([A-Z0-9_]+)=\"(.*)\"$ ]] && ./scripts/config --set-str "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
done < <(grep -E '^CONFIG_' "$FRAGMENT")
./scripts/config --set-str LOCALVERSION "-microsoft-standard-WSL2${LOCALVERSION_SUFFIX}"
# olddefconfig is non-interactive by design; piping `yes ''` into it (the
# prior-art habit for oldconfig) dies of SIGPIPE under pipefail.
make olddefconfig

echo "==> Verifying fragment took effect (strict-superset check, R1)"
for opt in CONFIG_ANDROID_BINDER_IPC=y CONFIG_ANDROID_BINDERFS=y; do
    grep -qx "$opt" .config || die "$opt missing from final .config"
done
grep -qx 'CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder"' .config \
    || die "binder devices string wrong in final .config"
# Nothing Microsoft enables may be lost: every =y/=m in their config must
# survive in ours (value changes y<->m also count as drift). Toolchain
# capability probes (GCC_/CC_/LD_/AS_/... options) are excluded — they are
# re-evaluated by olddefconfig for the build machine's compiler and vary
# with it, not with our fragment (first CI run flagged
# GCC_ASM_GOTO_OUTPUT_WORKAROUND and GCC_PLUGINS this way).
lost="$(comm -23 <(grep -E '^CONFIG_.*=(y|m)$' Microsoft/config-wsl | sort) \
                 <(grep -E '^CONFIG_.*=(y|m)$' .config | sort) \
        | grep -Ev '^CONFIG_(LOCALVERSION|GCC_|CC_|LD_|AS_|CLANG_|RUSTC_|RUST_|PAHOLE_|OBJTOOL_|TOOLS_)' || true)"
[[ -z "$lost" ]] || die "not a strict superset of Microsoft's config — lost options:
$lost"

echo "==> Building"
make -j"$(nproc)" bzImage modules
make INSTALL_MOD_PATH="$PWD/modules-staging" modules_install
KREL="$(make -s kernelrelease)"

echo "==> Packing modules vhdx (upstream helper)"
[[ -x Microsoft/scripts/gen_modules_vhdx.sh ]] || die "Microsoft/scripts/gen_modules_vhdx.sh missing — upstream layout changed"
sudo ./Microsoft/scripts/gen_modules_vhdx.sh "$PWD/modules-staging" "$KREL" "$OUT_DIR/modules-windroid-$TAG.vhdx"

cp arch/x86/boot/bzImage "$OUT_DIR/bzImage-windroid-$TAG"
cp .config "$OUT_DIR/config-windroid-$TAG"
( cd "$OUT_DIR" && sha256sum "bzImage-windroid-$TAG" "modules-windroid-$TAG.vhdx" "config-windroid-$TAG" > SHA256SUMS )

echo "==> Done: $OUT_DIR (kernelrelease: $KREL)"
cat "$OUT_DIR/SHA256SUMS"
