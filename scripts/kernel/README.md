# Kernel build and packaging

`build-kernel.sh` builds the arm64 `Image`, modules and the TB320FC DTB from a
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
| `--src` | Kernel source tree with the TB320FC patches. |
| `--out` | Kernel build directory (`O=`). Must already contain a `.config`. |
| `--artifacts` | Where the results go (see below). |
| `--baseline` | Packaging baseline (see below). |
| `--localversion` | Optional `CONFIG_LOCALVERSION`. Use a new one per experiment so its modules don't overwrite the running kernel's. |
| `-j` | Parallel jobs (default: all CPUs). |

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
  sm8475-lenovo-tb320fc.dtb        upstream DTB
  sm8475-lenovo-tb320fc-abl.dtb    + tb320fc-abl.dtso (what Lenovo's ABL needs)
  modules.tar.gz                   extract on the tablet with: tar -xzf ... -C /
  source.commit  source.patch      exact source used
  flash/boot.img  flash/vendor_boot.img  flash/SHA256SUMS  flash/manifest.json
```

Install the modules before flashing, then run `depmod <kernel.release>`.
Arch Linux ARM has `/lib -> usr/lib`, so the archive ships `usr/lib/modules`;
use `tar --keep-directory-symlink` if your tar would otherwise replace the link.
