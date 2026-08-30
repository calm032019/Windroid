# kernel/ — binder-enabled WSL2 kernel

The stock Microsoft WSL2 kernel ships with binder compiled out
(`# CONFIG_ANDROID_BINDER_IPC is not set`), and Waydroid cannot run — or
even `init` — without binder. This directory builds Microsoft's kernel from
their exact tag + config with only the additions in `windroid.fragment`.

**Risk R1 is the design constraint here:** the `.wslconfig` kernel is global
to every WSL2 distro on the machine (including Docker Desktop's). The build
therefore refuses to produce a kernel whose config is not a strict superset
of Microsoft's (`build.sh` fails the build if any Microsoft `=y`/`=m` option
was lost).

## Usage

```bash
# Inside any Linux env with kernel build deps (see below):
kernel/build.sh linux-msft-wsl-6.6.123.2          # explicit upstream tag
kernel/build.sh --from-uname                       # match the running WSL kernel
```

Build deps (upstream README + prior art):
`build-essential flex bison dwarves libssl-dev libelf-dev cpio qemu-utils bc kmod rsync python3`.
The modules-vhdx step uses upstream's own `Microsoft/scripts/gen_modules_vhdx.sh`
(needs sudo + qemu-utils).

Outputs (per tag): `bzImage-windroid-<tag>`, `modules-windroid-<tag>.vhdx`,
`config-windroid-<tag>`, `SHA256SUMS`. Wire into `%USERPROFILE%\.wslconfig`:

```ini
[wsl2]
kernel=C:\\Windroid\\kernel\\bzImage-windroid-<tag>
kernelModules=C:\\Windroid\\kernel\\modules-windroid-<tag>.vhdx
```

then `wsl --shutdown`. (The installer does this merge for users; this README
is for developers.)

## Which tag to build

Match the tag to the kernel the user's WSL actually runs (`uname -r` minus
the `-microsoft-standard-WSL2` suffix), falling back to the newest tag of
the same `major.minor` — the same policy ddcash proved. CI builds the
current 6.6.y and 6.18.y heads on every upstream tag bump (canary
workflow); the release manifest pins the exact tag per release.

## Verifying binder on a booted kernel

```bash
sudo mkdir -p /dev/binderfs && sudo mount -t binder binder /dev/binderfs \
  && ls /dev/binderfs && sudo umount /dev/binderfs && sudo rmdir /dev/binderfs && echo BINDER_OK
```

No ashmem anywhere: gone from 6.6+ kernels, Waydroid uses memfd instead
(`docs/UPSTREAM-FACTS.md` §1/§5).
