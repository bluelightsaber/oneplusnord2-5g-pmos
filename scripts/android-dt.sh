#!/bin/bash
# Capture the device tree LK passes in a NORMAL Android boot (with every carve-out: modem, SCP, ADSP …) without
# root: /proc/device-tree is readable from `adb shell`; serialize it file by file (base64), rebuild it on the host
# and decompile with the kernel tree's dtc. Read-only on the phone. Usage: android-dt.sh OUTDIR
set -eu
N=/srv/nord2-pmos; PT=$N/platform-tools; O=${1:?outdir}; mkdir -p $O
DTC=$(ls $N/src/build-*/scripts/dtc/dtc | head -1)
$PT/adb shell 'cd /proc/device-tree && find . -type f | while read f; do echo "@@ $f"; base64 -w0 "$f"; echo; done' > $O/dt.b64
rm -rf $O/device-tree; mkdir -p $O/device-tree
python3 - "$O/dt.b64" "$O/device-tree" <<'PY'
import sys, os, base64
src, root = sys.argv[1], sys.argv[2]; n = 0
lines = open(src).read().split('\n')
for i in range(0, len(lines) - 1, 2):
    h, d = lines[i], lines[i + 1]
    if not h.startswith('@@ '): continue
    p = os.path.join(root, h[3:].strip().lstrip('./'))
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, 'wb').write(base64.b64decode(d)); n += 1
print(n, "properties")
PY
$DTC -q -I fs -O dts -o $O/normal.dts $O/device-tree && wc -l $O/normal.dts
