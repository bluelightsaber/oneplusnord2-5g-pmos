#!/bin/bash
# Build the MT6893 mainline kernel (Image.gz + dtbs [+ modules]) out of tree, at low priority.
# Toolchain: kernel.org GCC 14.2 nolibc reused read-only from another MediaTek project.
# Usage: [MODULES=1] build-kernel.sh OUTNAME [defconfig]   -> $N/src/build-OUTNAME, log build.log
# (modules are not shipped: everything denniz needs is built in, so they are skipped unless MODULES=1)
set -u
renice -n 19 -p $$ >/dev/null; ionice -c3 -p $$
N=/srv/nord2-pmos; SRC=$N/src/linux-mt6893; O=$N/src/build-${1:?name}; CFG=${2:-chopin_defconfig}
export ARCH=arm64 CROSS_COMPILE=/opt/gcc-14.2.0-nolibc/aarch64-linux/bin/aarch64-linux-
mkdir -p $O; cd $SRC || exit 1
{ [ -f $O/.config ] || make O=$O $CFG; } && make O=$O -j4 Image.gz dtbs ${MODULES:+modules} > $O/build.log 2>&1
rc=$?; echo "BUILD rc=$rc $(date)" >> $O/build.log; tail -5 $O/build.log; exit $rc
