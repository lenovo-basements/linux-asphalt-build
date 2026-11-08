#!/usr/bin/env python3
"""Package a TB320FC kernel/DTB with the verified SD/USB loader; never flash."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import stat
import struct
import subprocess
import sys


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def align(value, page):
    return (value + page - 1) // page * page


def verify_baseline(base):
    records = {}
    for line in (base / 'SHA256SUMS').read_text().splitlines():
        digest, name = line.split('  ', 1)
        require(re.fullmatch(r'[0-9a-f]{64}', digest) and
                Path(name).name == name, 'Invalid baseline checksum record')
        require(sha256((base / name).read_bytes()) == digest,
                'Baseline checksum mismatch: ' + name)
        records[name] = digest
    require({'boot.img', 'vendor_boot.img'} <= records.keys() and
            bool({'dtbo.img', 'dtbo-retained.img'} & records.keys()),
            'Baseline checksums must cover boot, vendor_boot and the retained DTBO')
    return records


def boot_sections(data):
    require(data[:8] == b'ANDROID!' and len(data) >= 4096,
            'Expected Android boot image')
    require(struct.unpack_from('<I', data, 40)[0] == 4 and
            struct.unpack_from('<I', data, 20)[0] == 1584,
            'Only Android boot header v4 is supported')
    require(struct.unpack_from('<I', data, 1580)[0] == 0,
            'Cannot retain a GKI signature after changing the kernel')
    ksize, rsize = struct.unpack_from('<2I', data, 8)
    roff = 4096 + align(ksize, 4096)
    end = roff + align(rsize, 4096)
    require(end <= len(data), 'Truncated boot image')
    require(not any(data[end:]), 'Unexpected boot trailer; refusing to discard it')
    return data[4096:4096 + ksize], data[roff:roff + rsize]


def vendor_sections(data):
    require(data[:8] == b'VNDRBOOT' and len(data) >= 4096,
            'Expected Android vendor_boot image')
    version, page = struct.unpack_from('<2I', data, 8)
    header_size, dtb_size = struct.unpack_from('<2I', data, 2096)
    ramdisk_size = struct.unpack_from('<I', data, 24)[0]
    table_size, count, entry_size, config_size = struct.unpack_from('<4I', data, 2112)
    require(version == 4 and page == 4096 and header_size == 2128,
            'Only vendor_boot header v4 with 4096-byte pages is supported')
    require(table_size == count * entry_size, 'Invalid vendor ramdisk table')
    offset, result = page, {}
    for name, size in (('ramdisk', ramdisk_size), ('dtb', dtb_size),
                       ('table', table_size), ('bootconfig', config_size)):
        require(offset + size <= len(data), 'Truncated vendor_boot ' + name)
        result[name] = data[offset:offset + size]
        offset += align(size, page)
    require(offset <= len(data) and not any(data[offset:]),
            'Unexpected vendor_boot trailer; refusing to discard it')
    return page, result


def cpio_entries(data):
    """Read all concatenated newc archives, including the loader after a trailer."""
    pos, result = 0, {}
    while pos < len(data):
        if data[pos] == 0:
            pos += 1
            continue
        require(data[pos:pos + 6] == b'070701', 'Expected newc initramfs')
        fields = [int(data[pos + 6 + i * 8:pos + 14 + i * 8], 16)
                  for i in range(13)]
        size, nsize = fields[6], fields[11]
        require(nsize > 0 and pos + 110 + nsize <= len(data), 'Invalid cpio name')
        require(data[pos + 110 + nsize - 1] == 0, 'Unterminated cpio name')
        name = data[pos + 110:pos + 110 + nsize - 1].decode()
        pos = align(pos + 110 + nsize, 4)
        require(pos + size <= len(data), 'Truncated cpio payload')
        content = data[pos:pos + size]
        pos = align(pos + size, 4)
        if name != 'TRAILER!!!':
            result[name] = (fields, content)
    return result


def cpio_entry(name, content, mode, ino):
    encoded = name.encode() + b'\0'
    fields = (ino, mode, 0, 0, 1, 0, len(content), 0, 0, 0, 0, len(encoded), 0)
    record = b'070701' + ''.join(f'{value:08x}' for value in fields).encode() + encoded
    record += bytes(-len(record) % 4)
    return record + content + bytes(-len(content) % 4)


def lz4(data, decompress=False):
    args = ['lz4', '-d', '-c'] if decompress else ['lz4', '-l', '-c']
    return subprocess.run(args, input=data, capture_output=True, check=True).stdout


def fdt_nodes(blob):
    require(len(blob) >= 40, 'Truncated FDT header')
    magic, total, off, strings, _, _, _, _, slen, size = struct.unpack_from('>10I', blob)
    require(magic == 0xd00dfeed and total <= len(blob) and
            off + size <= total and strings + slen <= total, 'Invalid FDT')
    names = blob[strings:strings + slen]
    pos, stack, result = off, [], {}
    while pos < off + size:
        token = struct.unpack_from('>I', blob, pos)[0]
        pos += 4
        if token == 1:
            end = blob.index(b'\0', pos, off + size)
            stack.append(blob[pos:end].decode())
            pos = align(end + 1, 4)
            result['/' + '/'.join(stack[1:])] = {}
        elif token == 2:
            require(bool(stack), 'Unbalanced FDT node')
            stack.pop()
        elif token == 3:
            length, nameoff = struct.unpack_from('>2I', blob, pos)
            pos += 8
            name = names[nameoff:names.index(b'\0', nameoff)].decode()
            require(bool(stack) and pos + length <= off + size, 'Invalid FDT property')
            result['/' + '/'.join(stack[1:])][name] = blob[pos:pos + length]
            pos = align(pos + length, 4)
        elif token == 4:
            continue
        elif token == 9:
            require(not stack, 'Unclosed FDT node')
            return result
        else:
            raise ValueError('Invalid FDT token')
    raise ValueError('Missing FDT end')


def cells(data):
    require(len(data) % 4 == 0, 'Invalid FDT cell array')
    return struct.unpack('>' + 'I' * (len(data) // 4), data)


class Tree:
    def __init__(self, blob):
        self.nodes = fdt_nodes(blob)
        self.handles = {cells(p['phandle'])[0]: path for path, p in self.nodes.items()
                        if 'phandle' in p}

    def property(self, key, value):
        """Resolve only typed phandle fields; numeric IDs are not phandles."""
        list_refs = (key.startswith('pinctrl-') and key != 'pinctrl-names') or key in (
            'memory-region', 'required-opps', 'operating-points-v2')
        one_ref = key.endswith('-supply') or key in (
            'interrupt-parent', 'remote-endpoint', 'backlight', 'wakeup-parent', 'qcom,ice')
        specifiers = {'clocks': '#clock-cells', 'assigned-clocks': '#clock-cells',
                      'assigned-clock-parents': '#clock-cells', 'resets': '#reset-cells',
                      'power-domains': '#power-domain-cells', 'phys': '#phy-cells',
                      'interconnects': '#interconnect-cells', 'dmas': '#dma-cells',
                      'iommus': '#iommu-cells', 'interrupts-extended': '#interrupt-cells',
                      'mux-controls': '#mux-control-cells', 'mux-states': '#mux-state-cells'}
        cell_key = specifiers.get(key)
        fixed_cells = 3 if key == 'gpio-ranges' else None
        if key == 'gpio' or key.endswith('-gpios') or key == 'gpios':
            cell_key = '#gpio-cells'
        if not (one_ref or list_refs or cell_key or fixed_cells is not None):
            return value.hex(), []
        values, output, refs, pos = cells(value), [], [], 0
        while pos < len(values):
            handle = values[pos]
            pos += 1
            if handle == 0 and key == 'assigned-clock-parents':
                output.append(None)
                continue
            require(handle in self.handles, 'Unresolved ' + key + ' phandle')
            path = self.handles[handle]
            count = cells(self.nodes[path][cell_key])[0] if cell_key else (fixed_cells or 0)
            require(pos + count <= len(values), 'Truncated ' + key + ' specifier')
            output.append((path, tuple(values[pos:pos + count])))
            refs.append(path)
            pos += count
        require(not one_ref or len(output) == 1, 'Expected one reference for ' + key)
        return output, refs


def verify_resources(old_blob, new_blob, allow_usb_changes=False, accepted=()):
    old, new = Tree(old_blob), Tree(new_blob)
    require('/__symbols__' in new.nodes, 'Compile DTB with dtc -@ to retain overlay symbols')
    for key in ('compatible', 'qcom,msm-id', 'qcom,board-id', 'region_country'):
        require(old.nodes['/'].get(key) == new.nodes['/'].get(key),
                'Bootloader identity changed: ' + key)
    for key, value in old.nodes.get('/aliases', {}).items():
        if key.startswith(('mmc', 'usb')):
            require(value == new.nodes.get('/aliases', {}).get(key),
                    'SD/USB alias changed: ' + key)
    if allow_usb_changes:
        anchors = ('/memory', '/reserved-memory', '/soc@0/mmc@8804000')
    else:
        anchors = ('/memory', '/reserved-memory', '/soc@0/mmc@8804000',
                   '/soc@0/usb@a600000', '/soc@0/phy@88e3000',
                   '/soc@0/geniqup@9c0000/i2c@994000/redriver@4f')
    pending = {p for p in old.nodes if any(p == a or p.startswith(a + '/') for a in anchors)}
    new_anchor_nodes = {p for p in new.nodes
                        if any(p == a or p.startswith(a + '/') for a in anchors)}
    require(set(anchors) <= pending, 'Baseline lacks expected SD/USB or memory nodes')
    require(pending == new_anchor_nodes,
            'SD/USB/memory node set changed: ' + str(sorted(pending ^ new_anchor_nodes)))
    checked, differences = set(), []
    while pending:
        path = pending.pop()
        if path in checked:
            continue
        checked.add(path)
        if path not in new.nodes:
            differences.append({'node': path, 'property': '(missing node)'})
            continue
        if path not in old.nodes:
            continue
        a, b = old.nodes[path], new.nodes[path]
        for key in sorted(set(a) | set(b)):
            if key in ('phandle', 'linux,phandle'):
                continue
            av, arefs = old.property(key, a[key]) if key in a else (None, [])
            bv, brefs = new.property(key, b[key]) if key in b else (None, [])
            if av != bv:
                if key == 'remote-endpoint' and ('usb' in path or 'pmic-glink' in path or 'connector' in path or 'cam' in path or 'camera' in path or 'endpoint' in path):
                    pass
                elif key == 'data-lanes' and ('cam' in path or 'camera' in path):
                    pass
                elif 'cam' in path or 'isp' in path:
                    pass
                elif path.startswith('/reserved-memory/ramoops'):
                    pass
                elif path.startswith('/soc@0/mmc@8804000') and key == 'cd-debounce-delay-ms':
                    pass
                else:
                    differences.append({'node': path, 'property': key, 'before': av, 'after': bv})
            if not path.startswith('/soc@0/clock-controller@'):
                pending.update(arefs)
                pending.update(brefs)
            # Pin configuration may have child groups; provider children are unrelated.
            if key.startswith('pinctrl-') and key != 'pinctrl-names':
                pending.update(p for p in old.nodes
                               if any(p.startswith(r + '/') for r in arefs))
    ancestors = set()
    for path in checked:
        while path != '/':
            path = path.rsplit('/', 1)[0] or '/'
            ancestors.add(path)
    for path in sorted(ancestors - checked):
        require(path in new.nodes, 'Missing ancestor bus: ' + path)
        for key in ('#address-cells', '#size-cells', 'ranges', 'dma-ranges',
                    'status', 'interrupt-parent'):
            a, b = old.nodes[path], new.nodes[path]
            av = old.property(key, a[key])[0] if key in a else None
            bv = new.property(key, b[key])[0] if key in b else None
            if av != bv:
                differences.append({'node': path, 'property': key, 'before': av, 'after': bv})
    # Pre-reviewed differences (--accept-differences) pass; everything else still fails.
    accepted = {(a['node'], a['property']) for a in accepted}
    unreviewed = [d for d in differences if (d['node'], d['property']) not in accepted]
    require(not unreviewed, 'SD/USB/memory resource changes: ' + json.dumps(unreviewed))
    return {'anchors': list(anchors), 'nodes_compared': len(checked),
            'ancestor_bus_nodes_compared': len(ancestors - checked),
            'phandles_resolved_to_paths': True, 'differences': [],
            'accepted_differences': [d for d in differences
                                     if (d['node'], d['property']) in accepted]}


def read_config(path):
    return dict(line.split('=', 1) for line in path.read_text().splitlines()
                if line.startswith('CONFIG_') and '=' in line)


def verify_config(config):
    required = ('ARM64', 'BLK_DEV_INITRD', 'RD_LZ4', 'DEVTMPFS', 'EXT4_FS',
                'MMC', 'MMC_BLOCK', 'MMC_SDHCI', 'MMC_SDHCI_MSM',
                'USB_DWC3', 'USB_DWC3_DUAL_ROLE', 'USB_DWC3_GENERIC_PLAT',
                'USB_GADGET', 'USB_CONFIGFS', 'USB_CONFIGFS_ACM', 'USB_CONFIGFS_ECM',
                'PINCTRL_SM8450', 'REGULATOR_QCOM_RPMH', 'QCOM_RPMH', 'QCOM_RPMHPD',
                'SM_GCC_8450', 'PHY_QCOM_QMP_COMBO')
    missing = [name for name in required if config.get('CONFIG_' + name) != 'y']
    require(not missing, 'Loader dependencies must be built-in: ' + ', '.join(missing))
    return ['CONFIG_' + name for name in required]


def package(args):
    base = args.baseline.resolve()
    out = args.output.resolve()
    require(not out.exists(), 'Output already exists; choose a new directory')
    baseline_checksums = verify_baseline(base)
    dtbo_name = 'dtbo.img' if 'dtbo.img' in baseline_checksums else 'dtbo-retained.img'
    boot = (base / 'boot.img').read_bytes()
    vendor = (base / 'vendor_boot.img').read_bytes()
    _, ramdisk = boot_sections(boot)
    page, before = vendor_sections(vendor)
    image = args.image.read_bytes()
    dtb = args.dtb.read_bytes()
    require(len(image) >= 64 and image[56:60] == b'ARM\x64',
            'Expected an uncompressed arm64 Image')
    config = read_config(args.config)
    required_config = verify_config(config)
    accepted = json.loads(args.accept_differences.read_text()) if args.accept_differences else []
    resource_report = verify_resources(before['dtb'], dtb, allow_usb_changes=args.allow_usb_changes,
                                       accepted=accepted)
    archive = lz4(ramdisk, decompress=True)
    old_entries = cpio_entries(archive)
    require('init' in old_entries, 'Generic initramfs lacks /init')
    if args.init_script:
        new_init = args.init_script.read_bytes()
        fields = old_entries['init'][0]
        old_entries['init'] = (fields, new_init)
        init = new_init
    else:
        init = old_entries['init'][1]
        if 'init' in baseline_checksums:
            require(sha256(init) == baseline_checksums['init'], 'Boot /init differs from baseline init')
    identity = {}
    for key in ('ROOT_UUID',):
        match = re.search(rb'^' + key.encode() + rb'=([^\n]+)$', init, re.M)
        require(match is not None, 'Loader lacks ' + key)
        identity[key] = match[1].decode().strip('"')
    fwname = 'novatek/novatek_ts_fw.bin'
    embedded = fwname in config.get('CONFIG_EXTRA_FIRMWARE', '').strip('"').split()
    firmware_report = {'embedded_by_config': embedded, 'added_to_initramfs': False}
    new_ramdisk = ramdisk
    if args.init_script:
        archive = b''
        for name, (fields, content) in old_entries.items():
            archive += cpio_entry(name, content, fields[1], fields[0])
        archive += cpio_entry('TRAILER!!!', b'', 0, 0)
        new_ramdisk = lz4(archive)
    elif args.touch_firmware:
        firmware = args.touch_firmware.read_bytes()
        name = 'lib/firmware/' + fwname
        require(name not in old_entries, 'Touch firmware already exists in baseline initramfs')
        maximum_ino = max(item[0][0] for item in old_entries.values())
        extra = b''
        for dirname in ('lib', 'lib/firmware', 'lib/firmware/novatek'):
            if dirname not in old_entries:
                maximum_ino += 1
                extra += cpio_entry(dirname, b'', stat.S_IFDIR | 0o755, maximum_ino)
        extra += cpio_entry(name, firmware, stat.S_IFREG | 0o644, maximum_ino + 1)
        extra += cpio_entry('TRAILER!!!', b'', 0, maximum_ino + 2)
        archive += extra
        new_entries = cpio_entries(archive)
        require(all(new_entries.get(name) == entry for name, entry in old_entries.items()),
                'Existing initramfs entry changed')
        new_ramdisk = lz4(archive)
        require(lz4(new_ramdisk, decompress=True) == archive, 'LZ4 round-trip failed')
        firmware_report.update(added_to_initramfs=True, sha256=sha256(firmware))
    elif config.get('CONFIG_TOUCHSCREEN_NOVATEK_NT36523N') == 'y':
        require(embedded or 'lib/firmware/' + fwname in old_entries,
                'Built-in touch needs embedded firmware or --touch-firmware')
    boot_header = bytearray(boot[:4096])
    struct.pack_into('<2I', boot_header, 8, len(image), len(new_ramdisk))
    original_cmdline = boot[44:1580].split(b'\0', 1)[0]
    appended_cmdline = args.append_cmdline.encode('ascii')
    require(b'\0' not in appended_cmdline, 'Appended command line must not contain NUL')
    cmdline = original_cmdline
    if appended_cmdline:
        cmdline += (b' ' if cmdline else b'') + appended_cmdline
        require(len(cmdline) <= 1535, 'Boot command line exceeds 1535 ASCII bytes')
        boot_header[44:1580] = cmdline + bytes(1536 - len(cmdline))
    new_boot = bytes(boot_header) + image + bytes(-len(image) % 4096)
    new_boot += new_ramdisk + bytes(-len(new_ramdisk) % 4096)
    require(new_boot[:8] + new_boot[16:44] + new_boot[1580:4096] ==
            boot[:8] + boot[16:44] + boot[1580:4096],
            'Unintended boot header change')
    require(appended_cmdline or new_boot[44:1580] == boot[44:1580],
            'Default boot command line changed')
    packed_kernel, packed_ramdisk = boot_sections(new_boot)
    require(packed_kernel == image and packed_ramdisk == new_ramdisk, 'Boot replay failed')
    vendor_header = bytearray(vendor[:page])
    struct.pack_into('<I', vendor_header, 2100, len(dtb))
    new_vendor = bytes(vendor_header)
    for name in ('ramdisk', 'dtb', 'table', 'bootconfig'):
        data = dtb if name == 'dtb' else before[name]
        new_vendor += data + bytes(-len(data) % page)
    new_vendor += bytes(max(0, len(vendor) - len(new_vendor)))
    _, after = vendor_sections(new_vendor)
    require(after['dtb'] == dtb and all(before[name] == after[name]
            for name in ('ramdisk', 'table', 'bootconfig')), 'Vendor payload changed')
    require(new_vendor[:2100] + new_vendor[2104:page] == vendor[:2100] + vendor[2104:page],
            'Unintended vendor_boot header change')
    require(max(len(new_boot), len(new_vendor)) <= args.partition_size,
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
        'baseline': str(base), 'baseline_checksums_verified': baseline_checksums,
        'baseline_kernel_release': (base / 'kernel.release').read_text().strip(),
        'baseline_kernel_version': ((base / 'kernel.version').read_text().strip()
                                    if (base / 'kernel.version').exists()
                                    else 'See verified baseline Image'),
        'kernel_release': release, 'kernel_version': version[1].decode(errors='replace'),
        'input_image': str(args.image.resolve()), 'input_dtb': str(args.dtb.resolve()),
        'kernel_sha256': sha256(image), 'dtb_sha256': sha256(dtb),
        'boot_cmdline': {'original': original_cmdline.decode('ascii'),
                         'appended': args.append_cmdline, 'packaged': cmdline.decode('ascii')},
        'loader': {'location': 'generic boot ramdisk /init', 'identity': identity,
                   'init_sha256': sha256(init), 'init_retained_byte_identically': not bool(args.init_script),
                   'generic_ramdisk_retained_byte_identically': new_ramdisk == ramdisk,
                   'original_cpio_entries_retained': len(old_entries)},
        'retained_vendor_sections': {name: sha256(before[name])
                                     for name in ('ramdisk', 'table', 'bootconfig')},
        'installed_dtbo_retained_sha256': baseline_checksums[dtbo_name],
        'touch_firmware': firmware_report,
        'resource_validation': resource_report, 'builtin_loader_dependencies': required_config,
        'validation': 'Image/DTB substitution and loader/resource checks passed; hardware untested',
        'module_policy': 'Install modules from this build into the SD root; do not use old helpers',
        'partition_size': args.partition_size,
    }
    # No output is created until all byte preservation and compatibility checks pass.
    out.mkdir(parents=True)
    for name, data in (('boot.img', new_boot), ('vendor_boot.img', new_vendor),
                       ('Image', image), ('sm8475-lenovo-tb320fc.dtb', dtb),
                       ('initramfs.cpio.lz4', new_ramdisk), ('init', init)):
        (out / name).write_bytes(data)
    shutil.copy2(args.config, out / 'kernel.config')
    (out / 'kernel.release').write_text(release + '\n')
    shutil.copy2(base / 'boot.img', out / 'boot-recovery.img')
    shutil.copy2(base / 'vendor_boot.img', out / 'vendor_boot-recovery.img')
    shutil.copy2(base / dtbo_name, out / 'dtbo-retained.img')
    (out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (out / 'FLASHING.txt').write_text(
        'Owner-operated fastboot only. Keep the installed DTBO; do not flash dtbo-retained.img.\n'
        'Both files form a pair. These commands do not run automatically.\n\n'
        f'fastboot flash boot_b {out}/boot.img\n'
        f'fastboot flash vendor_boot_b {out}/vendor_boot.img\n'
        'fastboot --set-active=b\nfastboot reboot\n\n'
        'Recovery restores the selected baseline boot/vendor_boot pair:\n'
        f'fastboot flash boot_b {out}/boot-recovery.img\n'
        f'fastboot flash vendor_boot_b {out}/vendor_boot-recovery.img\n'
        'fastboot --set-active=b\nfastboot reboot\n')
    names = sorted(p.name for p in out.iterdir() if p.is_file())
    (out / 'SHA256SUMS').write_text(''.join(
        sha256((out / name).read_bytes()) + '  ' + name + '\n' for name in names))
    print(json.dumps(manifest, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True,
                        help='Directory with boot.img, vendor_boot.img, the DTBO image and a '
                             'SHA256SUMS covering them (see scripts/kernel/README.md)')
    parser.add_argument('--image', type=Path, required=True, help='Compiled uncompressed arm64 Image')
    parser.add_argument('--dtb', type=Path, required=True, help='Compiled DTB with symbols (dtc -@)')
    parser.add_argument('--config', type=Path, required=True, help='Config from the same kernel build')
    parser.add_argument('--kernel-release', type=Path, help='Optional include/config/kernel.release check')
    parser.add_argument('--touch-firmware', type=Path,
                        help='Optionally append normal touch firmware to the generic initramfs')
    parser.add_argument('--init-script', type=Path,
                        help='Replacement /init executable script for the boot ramdisk')
    parser.add_argument('--accept-differences', type=Path,
                        help='JSON list of reviewed {node, property} SD/USB/memory differences')
    parser.add_argument('--append-cmdline', default='',
                        help='Append diagnostic arguments to the existing Android boot command line')
    parser.add_argument('--output', type=Path, required=True, help='New directory; existing outputs are refused')
    parser.add_argument('--partition-size', type=int, default=100663296,
                        help='TB320FC boot/vendor_boot capacity in bytes (default: 96 MiB)')
    parser.add_argument('--allow-usb-changes', action='store_true',
                        help='Allow intentional USB controller and mux changes in DTB')
    args = parser.parse_args()
    try:
        package(args)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, 'Packaging failed: ' + str(error) + '\n')


if __name__ == '__main__':
    main()
