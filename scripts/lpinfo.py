#!/usr/bin/env python3
"""List the logical partitions of an Android dynamic-partition (super) image, read-only.
Usage: lpinfo.py SUPER.img            -> name, first sector, sectors, byte offset/size of each linear extent
       lpinfo.py SUPER.img NAME OUT   -> copy partition NAME (single linear extent) to OUT"""
import struct, sys
f = open(sys.argv[1], 'rb')
f.seek(4096); g = f.read(4096)
magic, struct_size = struct.unpack_from('<II', g, 0)
assert magic == 0x616c4467, hex(magic)        # LP_METADATA_GEOMETRY_MAGIC
meta_max, slots, lbs = struct.unpack_from('<III', g, 8 + 32)
f.seek(4096 + 2 * 4096)                         # primary metadata, slot 0
h = f.read(256)
hmagic, major, minor, hsize = struct.unpack_from('<IHHI', h, 0)
assert hmagic == 0x414c5030, hex(hmagic)       # LP_METADATA_HEADER_MAGIC
tables_size = struct.unpack_from('<I', h, 12 + 32)[0]
desc = struct.unpack_from('<' + 'III' * 4, h, 12 + 32 + 4 + 32)  # partitions, extents, groups, block_devices
f.seek(4096 + 2 * 4096 + hsize); t = f.read(tables_size)
(po, pn, pe), (eo, en, ee) = desc[0:3], desc[3:6]
parts = []
for i in range(pn):
    b = t[po + i * pe: po + (i + 1) * pe]
    name = b[:36].split(b'\0')[0].decode(); attrs, first, num, grp = struct.unpack_from('<IIII', b, 36)
    exts = []
    for j in range(first, first + num):
        x = t[eo + j * ee: eo + (j + 1) * ee]
        nsec, ttype, tdata, tsrc = struct.unpack_from('<QIQI', x, 0); exts.append((nsec, ttype, tdata))
    parts.append((name, exts))
if len(sys.argv) == 2:
    for name, exts in parts:
        for nsec, ttype, tdata in exts:
            print(f"{name:24s} type={ttype} start_sector={tdata} sectors={nsec} offset={tdata*512} size={nsec*512}")
else:
    name, out = sys.argv[2], sys.argv[3]
    exts = dict(parts)[name]; o = open(out, 'wb')
    for nsec, ttype, tdata in exts:
        assert ttype == 0, "only linear extents"
        f.seek(tdata * 512); left = nsec * 512
        while left: c = f.read(min(left, 1 << 24)); o.write(c); left -= len(c)
    print(f"{name}: {sum(e[0] for e in exts)*512} bytes -> {out}")
