#!/bin/bash
# Build the denniz USB initramfs: busybox (static aarch64, reused from another MediaTek project) + our init.
# If the private connectivity firmware tarball exists (scripts/wifi-fw.sh), it is put into /lib/firmware of the
# initramfs: the built-in Wi-Fi driver probes at ~2-12 s and its NVRAM/pre-cal power-on races badly if the files
# only appear later (seen: power-on retry, RST_DRV_OWN_FAIL, firmware bus hang). The resulting image is private.
# Usage: [FW=…/wifi-fw.tgz] mk-initramfs.sh  -> $N/images/initramfs-usb.cpio.gz   (FW=none to leave it out)
set -euo pipefail
N=/srv/nord2-pmos; R=$N/images/initramfs-usb; OUT=$N/images/initramfs-usb.cpio.gz
FW=${FW:-$N/firmware-vendor/oos11-A20/wifi-fw.tgz}
rm -rf $R; mkdir -p $R/bin $R/dev $R/proc $R/sys $R/tmp
cp /opt/busybox-static/busybox $R/bin/busybox
cp $N/repo/initramfs-usb/init $R/init; chmod 755 $R/init $R/bin/busybox
if [ -f "$FW" ]; then
  T=$(mktemp -d); tar -C $T -xzf $FW; mkdir -p $R/lib; mv $T/usr/lib/firmware $R/lib/firmware; rm -rf $T
  chmod 700 $R; echo "firmware included: $(find $R/lib/firmware -type f | wc -l) files"
fi
(cd $R && find . | sort | cpio -o -H newc -R 0:0 --quiet | gzip -9n) > $OUT
[ -d $R/lib/firmware ] && chmod 600 $OUT
ls -la $OUT; sha256sum $OUT
