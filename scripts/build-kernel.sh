#!/bin/bash
# Build the MT6893 mainline kernel (Image.gz + dtbs + modules) out of tree, at low priority.
# Toolchain: kernel.org GCC 14.2 nolibc reused read-only from another MediaTek project.
# Usage: [MODULES=0] build-kernel.sh OUTNAME [defconfig]   -> $N/src/build-OUTNAME, log build.log
# Full kernel by default: every =m module is built and packed as $O/modules.tgz (usr/lib/modules/<ver>, stripped;
# usr/lib, not lib: pmOS has /lib -> usr/lib and busybox tar would replace the symlink), shipped by pmos-ram.sh.
set -u
renice -n ${NICE:-0} -p $$ >/dev/null; [ "${NICE:-0}" -ge 19 ] && ionice -c3 -p $$   # NICE=19 when buildhost is busy
N=/srv/nord2-pmos; SRC=$N/src/linux-mt6893; O=$N/src/build-${1:?name}; CFG=${2:-chopin_defconfig}
export ARCH=arm64 CROSS_COMPILE=/opt/gcc-14.2.0-nolibc/aarch64-linux/bin/aarch64-linux-
MODULES=${MODULES:-1}; [ "$MODULES" = 0 ] && MODULES=
mkdir -p $O; cd $SRC || exit 1
{ [ -f $O/.config ] || make O=$O $CFG; } && make O=$O -j${JOBS:-$(nproc)} Image.gz dtbs ${MODULES:+modules} > $O/build.log 2>&1
rc=$?
if [ $rc = 0 ] && [ -n "$MODULES" ]; then
  rm -rf $O/modinst $O/modules.tgz
  make O=$O INSTALL_MOD_PATH=$O/modinst/usr INSTALL_MOD_STRIP=1 -j${JOBS:-$(nproc)} modules_install >> $O/build.log 2>&1 && \
    rm -f $O/modinst/usr/lib/modules/*/build && \
    tar -C $O/modinst --owner=0 --group=0 -czf $O/modules.tgz usr && \
    echo "modules: $(find $O/modinst -name '*.ko*' | wc -l) files, $(du -sh $O/modules.tgz | cut -f1)" >> $O/build.log
  rc=$?
fi
echo "BUILD rc=$rc $(date)" >> $O/build.log; tail -5 $O/build.log; exit $rc
