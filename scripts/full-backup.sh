#!/bin/bash
# full-backup.sh (run on the build host, phone in pmOS with root via sudo): READ-ONLY full dump of the UFS.
#   - partition tables: sfdisk -d / -l of every LUN, first + last 1 MiB of each LUN (primary + backup GPT)
#   - whole small LUNs (sda, sdb: preloader pl_a / pl_b)
#   - every partition of sdc as NAME.img (userdata last, gzip -1 on the phone: mostly empty)
#   - sha256 computed on the phone AND on the host for every raw image; SHA256SUMS + verify.log
# Output: $N/backups/partitions/pre-persistent-YYYYmmdd-HHMM (mode 700, never published).
# Usage: full-backup.sh [--no-userdata]
set -euo pipefail
N=/srv/nord2-pmos; H=${PHONE:-user@172.16.42.1}; PW=~/oneplusnord2-password.txt
K="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -i $HOME/.ssh/id_ed25519_nord2"
O=$N/backups/partitions/pre-persistent-$(date +%Y%m%d-%H%M); mkdir -p $O; chmod 700 $N/backups $O; cd $O
ph() { ssh $K $H "sudo -S -p '' $1" < $PW; }        # $1: a simple command line (no quotes inside)
log() { echo "$(date +%T) $*" | tee -a backup.log; }

log "tables"
for d in sda sdb sdc; do
  ph "sfdisk -d /dev/$d" > $d.sfdisk 2> $d.sfdisk.err || true
  ph "sfdisk -l /dev/$d" > $d.sfdisk-l.txt 2>&1 || true
  ph "dd if=/dev/$d bs=1M count=1 status=none" > $d-first1M.bin
  sz=$(ph "blockdev --getsize64 /dev/$d"); echo "$d $sz" >> lun-sizes.txt
  ph "dd if=/dev/$d bs=1M skip=$(( sz / 1048576 - 1 )) count=1 status=none" > $d-last1M.bin
done
ph "cat /proc/partitions" > proc-partitions.txt
for p in $(ph "ls /sys/class/block" | grep -E '^sdc[0-9]+$' | sort -V); do
  echo "$p $(ph "cat /sys/class/block/$p/uevent" | grep PARTNAME | cut -d= -f2)"
done > partmap.txt

log "small LUNs"
for d in sda sdb; do ph "dd if=/dev/$d bs=4M status=none" > $d.img; ph "sha256sum /dev/$d" | awk -v f=$d.img '{print $1"  "f}' >> SHA256SUMS.phone; done

while read p name; do
  [ "$name" = userdata ] && continue
  log "$p $name"
  ph "dd if=/dev/$p bs=4M status=none" > $name.img
  ph "sha256sum /dev/$p" | awk -v f=$name.img '{print $1"  "f}' >> SHA256SUMS.phone
done < partmap.txt

log "host sha256"
sha256sum *.img *.bin *.sfdisk > SHA256SUMS
if sha256sum -c --quiet SHA256SUMS.phone > verify.log 2>&1; then log "VERIFY OK: phone == host for all raw images"
else log "VERIFY FAILED (see verify.log)"; fi

if [ "${1:-}" != --no-userdata ]; then
  up=$(awk '$2=="userdata"{print $1}' partmap.txt)
  log "userdata ($up) gzip -1"
  ph "dd if=/dev/$up bs=4M status=none | gzip -1" > userdata.img.gz   # dd as root, gzip as user (remote pipe)
  gzip -t userdata.img.gz && log "userdata gzip ok $(du -h userdata.img.gz | cut -f1)"
  sha256sum userdata.img.gz >> SHA256SUMS
fi
chmod -R go-rwx $O
log "DONE $O ($(du -sh $O | cut -f1))"
