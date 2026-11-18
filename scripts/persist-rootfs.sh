#!/bin/sh
# persist-rootfs.sh (on the phone, as root, while pmOS runs from RAM): copy the RUNNING, tested system to the
# `super` partition as btrfs (label pmos-root, subvolume @) for the persistent initramfs (PMOS_ROOT=super).
# DESTROYS `super` (Android's system/vendor/product): run only after a full backup, with CONFIRM=super.
# Excluded: pseudo filesystems and other mounts (-x), /tmp, /run, /var/tmp, the RAM journal.
set -eu
PART=${PART:-super}; M=/mnt/persist
D=""; for u in /sys/class/block/*/uevent; do grep -qx "PARTNAME=$PART" $u && D=/dev/$(basename ${u%/uevent}); done
[ -n "$D" ] || { echo "no partition $PART"; exit 1; }
[ "$(findmnt -n -o FSTYPE /)" = tmpfs ] || { echo "refusing: / is not the RAM rootfs"; exit 1; }
grep -q "^$D " /proc/mounts && { echo "refusing: $D is mounted"; exit 1; }
[ "${CONFIRM:-}" = "$PART" ] || { echo "refusing: set CONFIRM=$PART to format $D"; exit 1; }
echo "target $PART = $D ($(( $(cat /sys/class/block/${D#/dev/}/size) / 2048 )) MiB)"

command -v rsync >/dev/null && command -v chattr >/dev/null || apk add -q rsync e2fsprogs-extra
mkfs.btrfs -f -q -L pmos-root $D
mkdir -p $M; mount -o noatime,compress=zstd:1 $D $M
btrfs subvolume create $M/@ >/dev/null
mkdir -p $M/@/var/log $M/@/var/tmp; chattr +C $M/@/var/log $M/@/var/tmp   # no CoW for logs and scratch
rsync -aHAXx --numeric-ids --exclude=/tmp/* --exclude=/run/* --exclude=/var/tmp/* --exclude=/var/log/journal/* / $M/@/
mkdir -p $M/@/proc $M/@/sys $M/@/dev $M/@/run $M/@/tmp; chmod 1777 $M/@/tmp $M/@/var/tmp

# fstab: only the root (the RAM rootfs had none that applies here); data partition comes later, nofail
cp -p $M/@/etc/fstab $M/@/etc/fstab.ram 2>/dev/null || true
printf '# denniz persistent install: btrfs on the super partition\nLABEL=pmos-root / btrfs noatime,compress=zstd:1,subvol=@ 0 0\n' > $M/@/etc/fstab
mkdir -p $M/@/etc/systemd/journald.conf.d $M/@/var/log/journal
printf '[Journal]\nStorage=persistent\nSystemMaxUse=50M\n' > $M/@/etc/systemd/journald.conf.d/10-denniz-persistent.conf
echo "persistent install from the RAM system, $(date -Is), kernel $(uname -r)" > $M/@/etc/denniz-persistent

sync; df -h $M | tail -1; btrfs subvolume list $M; umount $M
echo "PERSIST-ROOTFS DONE"
