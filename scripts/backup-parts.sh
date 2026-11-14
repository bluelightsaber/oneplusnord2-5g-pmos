#!/bin/bash
# Full partition backup of the Nord 2 (read-only on the phone):
#   adb reboot bootloader -> fastboot boot TWRP (RAM only, nothing flashed) -> dump every partition except
#   userdata over adb (root in TWRP) to buildhost with sha256 checked on both sides -> reboot to Android.
# Output stays in backups/partitions/<tag>/ (never in the repo).
set -u
N=/srv/nord2-pmos; SER=${SERIAL:?set SERIAL to the phone serial}
ADB="$N/platform-tools/adb -s $SER"; FB="$N/platform-tools/fastboot -s $SER"
IMG=$N/firmware-vendor/twrp/twrp-3.7.0_11-0-denniz.img
OUT=$N/backups/partitions/oos11-A20-$(date +%Y%m%d-%H%M)
mkdir -p "$OUT"; cd "$OUT" || exit 1
log() { echo "[$(date +%T)] $*"; }

log "build: $($ADB shell getprop ro.build.display.id | tr -d '\r')"
$ADB reboot bootloader
for i in $(seq 1 45); do timeout 3 $FB devices 2>/dev/null | grep -q "$SER" && break; sleep 2; done
timeout 3 $FB devices | grep -q "$SER" || { log "NO-FASTBOOT"; exit 1; }
log "fastboot up; fastboot boot TWRP (RAM)"
timeout 120 $FB boot "$IMG" 2>&1; rc=$?
log "fastboot boot rc=$rc"
[ $rc -eq 0 ] || { log "FASTBOOT-BOOT-FAILED"; timeout 20 $FB reboot; exit 1; }
for i in $(seq 1 90); do st=$($ADB get-state 2>/dev/null); [ "$st" = recovery ] && break; sleep 2; done
log "adb state: $($ADB get-state 2>&1)"
[ "$($ADB get-state 2>/dev/null)" = recovery ] || { log "NO-RECOVERY-ADB"; exit 1; }
sleep 5
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
while read -r n dev; do
  case "$n" in userdata|sda|sdb|sdc|sdd) continue;; esac
  case "$dev" in /dev/block/sd[a-z]) continue;; esac
  [ -n "${SEEN[$dev]:-}" ] && { echo "$n -> alias of ${SEEN[$dev]}" >> aliases.txt; continue; }
  SEEN[$dev]=$n
  dump "$n" "$dev"
done < map.txt
# boot LUNs (preloader) and partition tables
dump lun-sda /dev/block/sda
dump lun-sdb /dev/block/sdb
$ADB exec-out "dd if=/dev/block/sdc bs=1048576 count=1 2>/dev/null" > lun-sdc-first1M.bin
$ADB shell 'sgdisk --print /dev/block/sdc 2>/dev/null || true' > gpt-sdc.txt
log "DONE total=$TOTAL fail=$FAIL dir=$OUT"; du -sh "$OUT"
chmod -R go-rwx "$OUT"
log "rebooting to Android"; $ADB reboot
[ $FAIL -eq 0 ] && echo BACKUP-OK || echo BACKUP-WITH-FAILURES
