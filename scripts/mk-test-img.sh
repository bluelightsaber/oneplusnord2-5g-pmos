#!/bin/bash
# Pack a recovery-slot test image: our Image.gz (board DTB embedded in the kernel) + initramfs + the STOCK
# dtb section (Android DT table; LK applies dtbo to it, the kernel then swaps in its own tree) + TWRP's
# recovery_dtbo, i.e. the same structure TWRP boots from the recovery partition with.
# Kernel at 0x40080000 like stock: LK reserves kernel_addr_mb at 0x40080000 (0x7c00000) and ASSERTs
# (mt_boot.c:567, reboot as "lk_crash") if the header asks for anything else (seen with 0x40200000).
# Usage: mk-test-img.sh NAME [BUILD=denniz] [INITRAMFS=initramfs-usb.cpio.gz]  -> $N/images/test-NAME.img
set -euo pipefail
N=/srv/nord2-pmos; NAME=$1; BUILD=${2:-denniz}; IR=$N/images/${3:-initramfs-usb.cpio.gz}
B=$N/backups/partitions/oos11-A20-20261114-1932; ST=$N/images/stock
K=$N/src/build-$BUILD/arch/arm64/boot/Image.gz
[ -f $ST/boot-a20.dtbtable ] || python3 $N/repo/scripts/bootimg2.py extract-dtb $B/boot.img $ST/boot-a20.dtbtable
[ -f $ST/twrp-recovery-dtbo.img ] || python3 - $B/recovery.img $ST/twrp-recovery-dtbo.img <<'PY'
import struct, sys
d = open(sys.argv[1], 'rb').read(); sz, off = struct.unpack_from('<IQ', d, 1632)
open(sys.argv[2], 'wb').write(d[off:off + sz]); print('recovery_dtbo', sz, 'bytes')
PY
OUT=$N/images/test-$NAME.img
python3 $N/repo/scripts/bootimg2.py pack $OUT --kernel $K --ramdisk $IR --dtb $ST/boot-a20.dtbtable \
  --recovery-dtbo $ST/twrp-recovery-dtbo.img --kernel-offset 0x00080000
S=$(stat -c %s $OUT); [ $S -le 134217728 ] || { echo "too big for recovery (128 MiB): $S"; exit 1; }
sha256sum $OUT | tee $OUT.sha256
echo "kernel: $(strings $N/src/build-$BUILD/vmlinux 2>/dev/null | grep -m1 '^Linux version' || true)"
