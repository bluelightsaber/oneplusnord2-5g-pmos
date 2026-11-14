#!/usr/bin/env python3
"""Minimal Android boot image v2 tool (no AOSP mkbootimg needed).
  bootimg2.py extract-dtb IN.img OUT.dtb          # dtb section of a v2 image (FDT or DT table, kept as is)
  bootimg2.py pack OUT.img --kernel K --ramdisk R --dtb D [--recovery-dtbo O]
        [--base 0x40000000 --kernel-offset 0x00080000 --ramdisk-offset 0x11100000
         --tags-offset 0x07c80000 --dtb-offset 0x07c80000 --cmdline STR --os-version 0x16000164]
Layout and header follow AOSP mkbootimg v2 (page size 2048, header_size 1660, SHA-1 id)."""
import argparse, hashlib, struct, sys
PAGE = 2048
def pad(n): return (PAGE - n % PAGE) % PAGE

def extract_dtb(img, out):
    d = open(img, 'rb').read()
    assert d[:8] == b'ANDROID!'
    ks, ka, rs, ra, ss, sa, ta, ps, hv = struct.unpack_from('<9I', d, 8)
    assert hv == 2 and ps == PAGE, (hv, ps)
    rdtbo_sz, rdtbo_off, hs = struct.unpack_from('<IQI', d, 1632)
    dtb_sz, dtb_addr = struct.unpack_from('<IQ', d, 1648)
    off = PAGE
    for n in (ks, rs, ss, rdtbo_sz): off += n + pad(n)
    blob = d[off:off + dtb_sz]
    # MTK LK: the dtb section is an Android DT table (magic d7b7ab1e, like dtbo), not a bare FDT; keep it whole
    assert blob[:4] in (b'\xd0\x0d\xfe\xed', b'\xd7\xb7\xab\x1e'), 'no FDT/DT-table magic at dtb offset'
    open(out, 'wb').write(blob); print(f'dtb {dtb_sz:#x} bytes (addr {dtb_addr:#x}) -> {out}')

def pack(a):
    k = open(a.kernel, 'rb').read(); r = open(a.ramdisk, 'rb').read(); dtb = open(a.dtb, 'rb').read()
    o = open(a.recovery_dtbo, 'rb').read() if a.recovery_dtbo else b''
    base = int(a.base, 0)
    sha = hashlib.sha1()
    for blob in (k, r, b'', o, dtb):
        sha.update(blob); sha.update(struct.pack('<I', len(blob)))
    cmd = a.cmdline.encode(); assert len(cmd) < 512
    o_off = PAGE + len(k) + pad(len(k)) + len(r) + pad(len(r)) if o else 0
    h = struct.pack('<8s10I16s512s32s1024sIQIIQ', b'ANDROID!', len(k), base + int(a.kernel_offset, 0),
                    len(r), base + int(a.ramdisk_offset, 0), 0, 0,  # second: none (stock has addr 0)
                   
                    base + int(a.tags_offset, 0), PAGE, 2, int(a.os_version, 0), b'', cmd,
                    sha.digest().ljust(32, b'\0'), b'', len(o), o_off, 1660, len(dtb),
                    base + int(a.dtb_offset, 0))
    assert len(h) == 1660, len(h)
    with open(a.out, 'wb') as f:
        f.write(h + b'\0' * (PAGE - len(h)))
        for blob in (k, r, o, dtb): f.write(blob + b'\0' * pad(len(blob)))
    print(f'{a.out}: kernel {len(k)} ramdisk {len(r)} recovery_dtbo {len(o)} dtb {len(dtb)}')

p = argparse.ArgumentParser(); sp = p.add_subparsers(dest='cmd', required=True)
e = sp.add_parser('extract-dtb'); e.add_argument('img'); e.add_argument('out')
q = sp.add_parser('pack'); q.add_argument('out')
for n in ('--kernel', '--ramdisk', '--dtb'): q.add_argument(n, required=True)
q.add_argument('--recovery-dtbo'); q.add_argument('--base', default='0x40000000')
q.add_argument('--kernel-offset', default='0x00080000'); q.add_argument('--ramdisk-offset', default='0x11100000')
q.add_argument('--tags-offset', default='0x07c80000'); q.add_argument('--dtb-offset', default='0x07c80000')
q.add_argument('--cmdline', default='bootopt=64S3,32N2,64N2 buildvariant=user')
q.add_argument('--os-version', default='0x16000164')
a = p.parse_args()
extract_dtb(a.img, a.out) if a.cmd == 'extract-dtb' else pack(a)
