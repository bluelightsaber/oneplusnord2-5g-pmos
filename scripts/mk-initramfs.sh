#!/bin/bash
# Build the denniz USB initramfs: busybox (static aarch64, reused from another MediaTek project) + our init.
# Usage: mk-initramfs.sh  -> $N/images/initramfs-usb.cpio.gz
set -euo pipefail
N=/srv/nord2-pmos; R=$N/images/initramfs-usb; OUT=$N/images/initramfs-usb.cpio.gz
rm -rf $R; mkdir -p $R/bin $R/dev $R/proc $R/sys $R/tmp
cp /opt/busybox-static/busybox $R/bin/busybox
cp $N/repo/initramfs-usb/init $R/init; chmod 755 $R/init $R/bin/busybox
(cd $R && find . | sort | cpio -o -H newc -R 0:0 --quiet | gzip -9n) > $OUT
ls -la $OUT; sha256sum $OUT
