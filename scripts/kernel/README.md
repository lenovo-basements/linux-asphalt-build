# Kernel build and packaging

`build-kernel.sh` builds the arm64 `Image`, modules and the asphalt (ROW) DTB from a
kernel tree, then repackages flashable `boot.img` + `vendor_boot.img`.
It never flashes anything.

```sh
scripts/kernel/build-kernel.sh \
    --src ~/linux \
    --out /tmp/asphalt-build \
    --artifacts ./out/my-build \
    --baseline ~/asphalt-baseline \
    --localversion -asphalt
```

| Option | Meaning |
| --- | --- |
| `--src` | Kernel source tree with the asphalt patches. |
| `--out` | Kernel build directory (`O=`). Must already contain a `.config`. |
| `--artifacts` | Where the results go (see below). |
| `--baseline` | Packaging baseline (see below). |
| `--localversion` | Optional `CONFIG_LOCALVERSION`. Use a new one per experiment so its modules don't overwrite the running kernel's. |
| `--fragment` | Config fragment merged into `.config` before `olddefconfig`; repeatable. `asphalt.config` is the device fragment; `asphalt-cfi.config` and `asphalt-lto.config` are one-off trials. Values that did not survive are listed in `<artifacts>/fragments/not-applied.txt`. |
| `--allow-compatible` | The exact root compatible packaging accepts although it differs from the baseline (space-separated). Defaults to the asphalt ROW list, since the baseline predates the tb320fc → asphalt rename. msm-id, board-id and region_country always have to match. |
| `--firmware-dir` | asphalt-firmware checkout (default: next to linux-asphalt-build). The baseline boot ramdisk carries the firmware the DSPs and GPU zap load before the root is mounted, still under the pre-rename names; packaging renames it (`package-boot.py --rename-firmware`) and checks every renamed file is byte-identical to this tree. The audio topology is not renamed: the sound card loads it from the rootfs, after root is mounted (built from `audio/Lenovo-Asphalt.m4` with `audio/build-topology.sh`). |
| `-j` | Parallel jobs (default: all CPUs). |

`package-boot.py` also takes `--kernel-compression {none,lz4,gz}` (default
`none`): the kernel is stored in boot.img as legacy-frame LZ4 or gzip, like
GKI's `Image.lz4` / `Image.gz`, and the bootloader decompresses it. With
`lz4` a 68.6 MB Image packs to about 24 MB, which leaves room in the 96 MiB
boot partition for options such as kCFI. Whether Lenovo ABL accepts it is
being verified.

## Host requirements

- **Linux:** `make`, LLVM/clang and lld (the build uses `LLVM=1`), `python3`,
  plus `lz4` for packaging. Native arm64 or cross from x86_64 both work.
- **macOS:** Homebrew `llvm`, `lld`, `make` (`gmake`), `gnu-sed`, `coreutils`,
  `lz4`. The headers in `host-compat/` let the kernel's host tools (modpost,
  gen_init_cpio, ...) build against Darwin's libc. The source tree must be on a
  case-sensitive volume.

## Output

```
<artifacts>/
  Image  kernel.config  kernel.release
  sm8475-lenovo-asphalt-row.dtb        upstream DTB
  sm8475-lenovo-asphalt-row-abl.dtb    + asphalt-abl.dtso (what Lenovo's ABL needs)
  modules.tar.gz                   extract on the tablet with: tar -xzf ... -C /
  source.commit  source.patch      exact source used
  flash/boot.img  flash/vendor_boot.img  flash/SHA256SUMS  flash/manifest.json
```

Install the modules before flashing, then run `depmod <kernel.release>`.
Arch Linux ARM has `/lib -> usr/lib`, so the archive ships `usr/lib/modules`;
use `tar --keep-directory-symlink` if your tar would otherwise replace the link.
