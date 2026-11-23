#!/usr/bin/env python3
"""Build the asphalt boot.img + vendor_boot.img from scratch; never flash.

No baseline needed: the boot ramdisk is made from this repo's initramfs/init,
a static aarch64 busybox and the asphalt-firmware tree (same layout as the
asphalt-firmware package). Header values are the ones Lenovo's ABL already
boots (Android boot header v4, mkbootimg default addresses).

    make-boot.py --image Image --dtb sm8475-lenovo-asphalt-row-abl.dtb \
        --config kernel.config --busybox busybox --firmware-dir ../asphalt-firmware \
        --output flash
"""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import stat
import struct
import subprocess
import sys

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location('package_boot', HERE / 'package-boot.py')
pb = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(pb)
require, sha256, align = pb.require, pb.sha256, pb.align

PAGE = 4096
# Android 17, security patch 2026-08: what the stock images ABL boots carry.
OS_VERSION = 0x220001a8
KERNEL_ADDR, RAMDISK_ADDR, TAGS_ADDR, DTB_ADDR = 0x8000, 0x1000000, 0x100, 0x1f00000
VENDOR_RAMDISK_TYPE_PLATFORM = 1
# Kept so the kernel strips the bootconfig ABL appends after the ramdisks.
VENDOR_CMDLINE = 'bootconfig'

# Same set as pkgbuilds/asphalt-firmware, minus what the kernel never asks for.
FIRMWARE_COMPONENTS = ('ath11k', 'awinic', 'cirrus', 'novatek', 'qca', 'qcom')
FIRMWARE_EXCLUDE = ('qcom/sensors',                        # hexagonrpcd, from the rootfs
                    'qcom/lenovo/asphalt/slpi/registry')   # sensor registry, rootfs only
FIRMWARE_LINKS = {'novatek/novatek_ts_fw.bin': 'asphalt-nt36523n.bin'}  # name the DT asks for
TOUCH_FIRMWARE = 'novatek/novatek_ts_fw.bin'


def check_busybox(data):
    """Static aarch64 ELF: the ramdisk has no libc to load."""
    require(data[:4] == b'\x7fELF' and data[4] == 2 and data[5] == 1,
            'busybox: expected a 64-bit little-endian ELF')
    require(struct.unpack_from('<H', data, 18)[0] == 183, 'busybox: not an aarch64 binary')
    phoff, = struct.unpack_from('<Q', data, 32)
    phentsize, phnum = struct.unpack_from('<2H', data, 54)
    for i in range(phnum):
        require(struct.unpack_from('<I', data, phoff + i * phentsize)[0] != 3,
                'busybox: dynamically linked (has PT_INTERP); a static build is required')
    version = re.search(rb'BusyBox v[0-9][0-9A-Za-z.\-]*', data)
    return version[0].decode() if version else 'unknown'


def firmware_files(root):
    """{path under lib/firmware: ('file', bytes) | ('link', target)}"""
    result = {}
    for comp in FIRMWARE_COMPONENTS:
        base = root / comp
        if not base.is_dir():
            continue
        for path in sorted(base.rglob('*')):
            rel = path.relative_to(root).as_posix()
            if any(part.startswith('.') for part in path.relative_to(root).parts):
                continue
            if any(rel == e or rel.startswith(e + '/') for e in FIRMWARE_EXCLUDE):
                continue
            if path.is_symlink():
                result[rel] = ('link', str(path.readlink()))
            elif path.is_file():
                result[rel] = ('file', path.read_bytes())
    for name, target in FIRMWARE_LINKS.items():
        require((Path(name).parent / target).as_posix() in result,
                f'--firmware-dir lacks {(Path(name).parent / target).as_posix()}')
        result.setdefault(name, ('link', target))
    require(result, 'No firmware found in --firmware-dir')
    return result


def newc(name, mode, ino, content=b'', rdev=(0, 0)):
    encoded = name.encode() + b'\0'
    fields = (ino, mode, 0, 0, 2 if stat.S_ISDIR(mode) else 1, 0, len(content),
              0, 0, rdev[0], rdev[1], len(encoded), 0)
    record = b'070701' + ''.join(f'{v:08x}' for v in fields).encode() + encoded
    record += bytes(-len(record) % 4)
    return record + content + bytes(-len(content) % 4)


def build_ramdisk(init, busybox, firmware):
    """Deterministic newc archive: parents first, all owned by root, mtime 0."""
    entries = {'bin': ('dir',), 'dev': ('dir',), 'lib': ('dir',), 'lib/firmware': ('dir',),
               'newroot': ('dir',), 'proc': ('dir',), 'run': ('dir',), 'sbin': ('dir',),
               'sys': ('dir',),
               'bin/busybox': ('file', busybox, 0o755), 'bin/sh': ('link', 'busybox'),
               'dev/console': ('chr', (5, 1)), 'init': ('file', init, 0o755)}
    for rel, item in firmware.items():
        parts = ('lib/firmware/' + rel).split('/')
        for i in range(3, len(parts)):
            entries.setdefault('/'.join(parts[:i]), ('dir',))
        entries['lib/firmware/' + rel] = item if item[0] == 'link' else ('file', item[1], 0o644)
    archive, ino = b'', 0
    for name in sorted(entries, key=lambda n: (n.count('/'), n)):
        ino += 1
        kind = entries[name]
        if kind[0] == 'dir':
            archive += newc(name, stat.S_IFDIR | 0o755, ino)
        elif kind[0] == 'file':
            archive += newc(name, stat.S_IFREG | kind[2], ino, kind[1])
        elif kind[0] == 'link':
            archive += newc(name, stat.S_IFLNK | 0o777, ino, kind[1].encode())
        else:
            archive += newc(name, stat.S_IFCHR | 0o600, ino, rdev=kind[1])
    archive += newc('TRAILER!!!', 0, 0)
    return archive, len(entries)


def boot_image(kernel, ramdisk, cmdline):
    raw = cmdline.encode('ascii')
    require(len(raw) <= 1535, 'Boot command line exceeds 1535 bytes')
    header = bytearray(PAGE)
    header[0:8] = b'ANDROID!'
    struct.pack_into('<4I', header, 8, len(kernel), len(ramdisk), OS_VERSION, 1584)
    struct.pack_into('<I', header, 40, 4)
    header[44:44 + len(raw)] = raw
    data = bytes(header) + kernel + bytes(-len(kernel) % PAGE)
    data += ramdisk + bytes(-len(ramdisk) % PAGE)
    require(pb.boot_sections(data) == (kernel, ramdisk), 'boot.img replay failed')
    return data


def vendor_boot_image(dtb, vendor_ramdisk, bootconfig=b''):
    header = bytearray(PAGE)
    header[0:8] = b'VNDRBOOT'
    struct.pack_into('<5I', header, 8, 4, PAGE, KERNEL_ADDR, RAMDISK_ADDR, len(vendor_ramdisk))
    raw = VENDOR_CMDLINE.encode('ascii')
    header[28:28 + len(raw)] = raw
    struct.pack_into('<I', header, 2076, TAGS_ADDR)
    struct.pack_into('<2I', header, 2096, 2128, len(dtb))
    struct.pack_into('<Q', header, 2104, DTB_ADDR)
    struct.pack_into('<4I', header, 2112, 108, 1, 108, len(bootconfig))
    table = bytearray(108)
    struct.pack_into('<3I', table, 0, len(vendor_ramdisk), 0, VENDOR_RAMDISK_TYPE_PLATFORM)
    data = bytes(header)
    for part in (vendor_ramdisk, dtb, bytes(table), bootconfig):
        data += part + bytes(-len(part) % PAGE)
    page, sections = pb.vendor_sections(data)
    require(page == PAGE and sections['dtb'] == dtb and sections['ramdisk'] == vendor_ramdisk,
            'vendor_boot.img replay failed')
    return data


def check_dtb(dtb):
    root = pb.fdt_nodes(dtb)
    require('/__symbols__' in root, 'Compile the DTB with dtc -@ (the DTBO overlay needs symbols)')
    missing = [k for k in ('qcom,msm-id', 'qcom,board-id') if k not in root['/']]
    require(not missing, 'DTB lacks ' + ', '.join(missing) +
            ': pass the -abl.dtb (apply-abl.sh output), not the upstream DTB')
    return {k: pb.cells(root['/'][k]) for k in ('qcom,msm-id', 'qcom,board-id')}


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--image', type=Path, required=True, help='Uncompressed arm64 Image')
    p.add_argument('--dtb', type=Path, required=True, help='ABL-ready DTB (apply-abl.sh output)')
    p.add_argument('--config', type=Path, required=True, help='.config of the same kernel build')
    p.add_argument('--kernel-release', type=Path, help='Optional include/config/kernel.release check')
    p.add_argument('--busybox', type=Path, required=True, help='Static aarch64 busybox binary')
    p.add_argument('--firmware-dir', type=Path, required=True, help='asphalt-firmware checkout')
    p.add_argument('--init', type=Path, default=HERE.parent.parent / 'initramfs' / 'init',
                   help='Loader /init (default: initramfs/init in this repo)')
    p.add_argument('--root-uuid', help='Replace the loader ROOT_UUID (default: keep the one in --init)')
    p.add_argument('--cmdline-file', type=Path, default=HERE / 'boot.cmdline',
                   help='Kernel command line (default: scripts/kernel/boot.cmdline)')
    p.add_argument('--append-cmdline', default='', help='Extra arguments for this build only')
    p.add_argument('--partition-size', type=int, default=100663296,
                   help='boot/vendor_boot capacity in bytes (default: 96 MiB)')
    p.add_argument('--output', type=Path, required=True, help='New directory; existing outputs are refused')
    args = p.parse_args()
    try:
        make(args)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        p.exit(1, 'Packaging failed: ' + str(error) + '\n')


def make(args):
    out = args.output.resolve()
    require(not out.exists(), 'Output already exists; choose a new directory')
    image = args.image.read_bytes()
    require(len(image) >= 64 and image[56:60] == b'ARM\x64', 'Expected an uncompressed arm64 Image')
    dtb = args.dtb.read_bytes()
    identity = check_dtb(dtb)
    config = pb.read_config(args.config)
    loader_deps = pb.verify_config(config)
    busybox = args.busybox.read_bytes()
    busybox_version = check_busybox(busybox)

    init = args.init.read_bytes()
    require(init.startswith(b'#!/bin/sh'), '--init must be a /bin/sh script')
    uuid_line = re.compile(rb'^ROOT_UUID="?([0-9a-fA-F-]+)"?$', re.M)
    require(len(uuid_line.findall(init)) == 1, '--init needs exactly one ROOT_UUID="..." line')
    if args.root_uuid:
        require(re.fullmatch(r'[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}', args.root_uuid),
                '--root-uuid must be a lowercase UUID')
        init = uuid_line.sub(b'ROOT_UUID="' + args.root_uuid.encode() + b'"', init)
    root_uuid = uuid_line.search(init)[1].decode()

    firmware = firmware_files(args.firmware_dir.resolve())
    if config.get('CONFIG_TOUCHSCREEN_NOVATEK_NT36523N') == 'y':
        require(TOUCH_FIRMWARE in firmware, 'Built-in touch needs ' + TOUCH_FIRMWARE)
    archive, entry_count = build_ramdisk(init, busybox, firmware)
    ramdisk = pb.lz4(archive)
    require(pb.lz4(ramdisk, decompress=True) == archive, 'LZ4 round-trip failed')
    require(set(pb.cpio_entries(archive)) >= {'init', 'bin/busybox', 'dev/console'},
            'ramdisk replay failed')
    # ABL wants a vendor ramdisk; an empty newc archive is enough for Linux.
    vendor_ramdisk = pb.lz4(newc('TRAILER!!!', 0, 0))

    cmdline = ' '.join(args.cmdline_file.read_text().split())
    if args.append_cmdline:
        cmdline += ' ' + args.append_cmdline.strip()
    require('rdinit=/init' in cmdline.split(), 'Command line must keep rdinit=/init')

    boot = boot_image(image, ramdisk, cmdline)
    vendor = vendor_boot_image(dtb, vendor_ramdisk)
    require(max(len(boot), len(vendor)) <= args.partition_size,
            'Package exceeds the boot/vendor_boot partition capacity')

    banners = list(re.finditer(rb'Linux version ([^\0\n]{1,300})[\0\n]', image))
    version = next((m for m in reversed(banners) if re.search(rb'#\d+\s', m[1])),
                   banners[-1] if banners else None)
    require(version is not None, 'Image lacks a Linux build version')
    release = version[1].decode(errors='replace').split(' ', 1)[0]
    if args.kernel_release:
        require(release == args.kernel_release.read_text().strip(),
                'Image version does not match --kernel-release file')

    manifest = {
        'mode': 'from scratch (no baseline)',
        'kernel_release': release, 'kernel_version': version[1].decode(errors='replace'),
        'input_image': str(args.image.resolve()), 'input_dtb': str(args.dtb.resolve()),
        'kernel_sha256': sha256(image), 'dtb_sha256': sha256(dtb),
        'dtb_identity': identity,
        'boot_cmdline': cmdline, 'vendor_cmdline': VENDOR_CMDLINE,
        'header': {'boot_version': 4, 'os_version': hex(OS_VERSION), 'page_size': PAGE,
                   'kernel_addr': hex(KERNEL_ADDR), 'ramdisk_addr': hex(RAMDISK_ADDR),
                   'tags_addr': hex(TAGS_ADDR), 'dtb_addr': hex(DTB_ADDR)},
        'loader': {'location': 'generic boot ramdisk /init', 'source': str(args.init.resolve()),
                   'identity': {'ROOT_UUID': root_uuid}, 'init_sha256': sha256(init)},
        'busybox': {'version': busybox_version, 'sha256': sha256(busybox)},
        'ramdisk': {'entries': entry_count, 'cpio_sha256': sha256(archive)},
        'firmware': {'source': str(args.firmware_dir.resolve()),
                     'files': {n: sha256(c) if k == 'file' else '-> ' + c
                               for n, (k, c) in sorted(firmware.items())}},
        'builtin_loader_dependencies': loader_deps,
        'validation': 'Images replayed and loader checks passed; hardware untested',
        'partition_size': args.partition_size,
    }
    out.mkdir(parents=True)
    for name, data in (('boot.img', boot), ('vendor_boot.img', vendor), ('Image', image),
                       ('sm8475-lenovo-asphalt-row.dtb', dtb), ('initramfs.cpio.lz4', ramdisk),
                       ('init', init)):
        (out / name).write_bytes(data)
    (out / 'kernel.config').write_bytes(args.config.read_bytes())
    (out / 'kernel.release').write_text(release + '\n')
    (out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (out / 'FLASHING.txt').write_text(
        'Owner-operated fastboot only. Both files form a pair. Keep the installed DTBO.\n'
        'These commands do not run automatically.\n\n'
        f'fastboot flash boot_b {out}/boot.img\n'
        f'fastboot flash vendor_boot_b {out}/vendor_boot.img\n'
        'fastboot --set-active=b\nfastboot reboot\n\n'
        'To go back: fastboot --set-active=a && fastboot reboot (Android), or flash the\n'
        'flash/ pair of a previous build that booted.\n')
    names = sorted(p.name for p in out.iterdir() if p.is_file())
    (out / 'SHA256SUMS').write_text(''.join(
        sha256((out / n).read_bytes()) + '  ' + n + '\n' for n in names))
    print(json.dumps({k: manifest[k] for k in ('kernel_release', 'boot_cmdline', 'loader', 'busybox',
                                               'ramdisk')}, indent=2))


if __name__ == '__main__':
    sys.exit(main())
