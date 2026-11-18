#!/bin/sh
# persist-data.sh (on the phone, as root, persistent install running): format `userdata` as btrfs (label pmos-data)
# with subvolumes @data, @docker, @containerd mounted at /data, /opt/docker (Docker data-root), /var/lib/containerd
# (same layout as the OnePlus 9 Pro).
# DESTROYS userdata (Android's data): run only after a verified full backup, with CONFIRM=userdata.
# Mounts are nofail (the system boots without them); docker/containerd require their mount (never fill the root).
set -eu
PART=userdata; M=/mnt/pmos-data
D=""; for u in /sys/class/block/*/uevent; do grep -qx "PARTNAME=$PART" $u && D=/dev/$(basename ${u%/uevent}); done
[ -n "$D" ] || { echo "no partition $PART"; exit 1; }
[ "$(findmnt -n -o FSTYPE /)" = btrfs ] && [ "$(findmnt -n -o SOURCE / | cut -d[ -f1)" != "$D" ] || { echo "refusing: not the persistent root"; exit 1; }
grep -q "^$D " /proc/mounts && { echo "refusing: $D is mounted"; exit 1; }
[ "${CONFIRM:-}" = "$PART" ] || { echo "refusing: set CONFIRM=$PART to format $D"; exit 1; }
echo "target $PART = $D ($(( $(cat /sys/class/block/${D#/dev/}/size) / 2097152 )) GiB)"

systemctl stop docker.socket docker.service containerd.service 2>/dev/null || true
mkfs.btrfs -f -q -L pmos-data $D
mkdir -p $M; mount -o noatime,compress=zstd:1 $D $M
for s in @data @docker @containerd; do btrfs subvolume create $M/$s >/dev/null; done
[ -d /var/lib/docker ] && rsync -aHAX --numeric-ids /var/lib/docker/ $M/@docker/
[ -d /var/lib/containerd ] && rsync -aHAX --numeric-ids /var/lib/containerd/ $M/@containerd/
umount $M; rmdir $M

O="noatime,compress=zstd:1,nofail,x-systemd.device-timeout=20s"
sed -i '/LABEL=pmos-data/d;/^# data: btrfs on the userdata/d' /etc/fstab
cat >> /etc/fstab <<EOT
# data: btrfs on the userdata partition (nofail: the system boots without it)
LABEL=pmos-data /data               btrfs $O,subvol=@data       0 0
LABEL=pmos-data /opt/docker         btrfs $O,subvol=@docker     0 0
LABEL=pmos-data /var/lib/containerd btrfs $O,subvol=@containerd 0 0
EOT
mkdir -p /etc/docker; printf '{
  "data-root": "/opt/docker"
}
' > /etc/docker/daemon.json
mkdir -p /etc/systemd/system/docker.service.d /etc/systemd/system/containerd.service.d
printf '[Unit]\nRequiresMountsFor=/opt/docker\n' > /etc/systemd/system/docker.service.d/10-denniz-data.conf
printf '[Unit]\nRequiresMountsFor=/var/lib/containerd\n' > /etc/systemd/system/containerd.service.d/10-denniz-data.conf
mkdir -p /data /opt/docker /var/lib/containerd
systemctl daemon-reload; mount -a
for t in /data /opt/docker /var/lib/containerd; do findmnt -n -o TARGET,SOURCE,FSTYPE $t; done
chown 10000:10000 /data
systemctl start containerd.service docker.socket docker.service
echo "PERSIST-DATA DONE"
