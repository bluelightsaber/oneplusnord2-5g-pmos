#!/bin/bash
# Full partition backup of the Nord 2 from TWRP (adb root, phone already in recovery). Read-only on the phone:
# dumps every partition except userdata, sha256 checked on both sides, stays in recovery at the end.
# Output stays in backups/partitions/<tag>/ (never in the repo).
set -u
N=/srv/nord2-pmos; SER=${SERIAL:?set SERIAL to the phone serial}
ADB="$N/platform-tools/adb -s $SER"
OUT=$N/backups/partitions/oos11-A20-$(date +%Y%m%d-%H%M)
mkdir -p "$OUT"; cd "$OUT" || exit 1
log() { echo "[$(date +%T)] $*"; }
[ "$($ADB get-state 2>/dev/null)" = recovery ] || { log "NOT-IN-RECOVERY"; exit 1; }
$ADB shell 'id; uname -a; getprop ro.twrp.version 2>/dev/null' | tee twrp-info.txt
$ADB shell 'ls -l /dev/block/by-name/' > by-name.txt
$ADB shell 'cat /proc/partitions' > proc-partitions.txt
# unique (name -> real block device), skip userdata and whole-disk/alias entries
$ADB shell 'cd /dev/block/by-name && for n in *; do echo "$n $(readlink -f $n)"; done' | tr -d '\r' > map.txt
FAIL=0; TOTAL=0
dump() {  # name device
  local n=$1 dev=$2 rs ls sz
  sz=$($ADB shell "blockdev --getsize64 $dev" | tr -d '\r')
  $ADB exec-out "dd if=$dev bs=4194304 2>/dev/null" > "$n.img"
  ls=$(sha256sum "$n.img" | cut -d' ' -f1)
  rs=$($ADB shell "sha256sum $dev" | cut -d' ' -f1 | tr -d '\r')
  local got=$(stat -c %s "$n.img")
  if [ "$ls" = "$rs" ] && [ "$got" = "$sz" ]; then echo "$ls  $n.img" >> SHA256SUMS; log "OK   $n ($dev, $sz B)"
  else log "FAIL $n ($dev) size=$got/$sz local=$ls phone=$rs"; FAIL=$((FAIL+1)); fi
  TOTAL=$((TOTAL+1))
}
declare -A SEEN
while read -r n dev <&3; do
  case "$n" in userdata|sda|sdb|sdc|sdd) continue;; esac
  case "$dev" in /dev/block/sd[a-z]) continue;; esac
  [ -n "${SEEN[$dev]:-}" ] && { echo "$n -> alias of ${SEEN[$dev]}" >> aliases.txt; continue; }
  SEEN[$dev]=$n
  dump "$n" "$dev"
done 3< map.txt
# boot LUNs (preloader) and partition tables
dump lun-sda /dev/block/sda
dump lun-sdb /dev/block/sdb
$ADB exec-out "dd if=/dev/block/sdc bs=1048576 count=1 2>/dev/null" > lun-sdc-first1M.bin
$ADB shell 'sgdisk --print /dev/block/sdc 2>/dev/null || true' > gpt-sdc.txt
log "DONE total=$TOTAL fail=$FAIL dir=$OUT"; du -sh "$OUT"
chmod -R go-rwx "$OUT"
log "staying in recovery (reboot manually when verified)"
[ $FAIL -eq 0 ] && echo BACKUP-OK || echo BACKUP-WITH-FAILURES
