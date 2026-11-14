#!/bin/bash
# Flash the verified official TWRP to the `recovery` partition (only write) and reboot straight into it,
# so Android never runs in between (it would regenerate the stock recovery from boot).
set -u
N=/srv/nord2-pmos; SER=${SERIAL:?set SERIAL to the phone serial}
ADB="$N/platform-tools/adb -s $SER"; FB="$N/platform-tools/fastboot -s $SER"
IMG=$N/firmware-vendor/twrp/twrp-3.7.0_11-0-denniz.img
log() { echo "[$(date +%T)] $*"; }
sha256sum -c <(awk '{print $1"  '"$IMG"'"}' "$IMG.sha256") >/dev/null || { log "TWRP-SHA-MISMATCH"; exit 1; }
if ! timeout 3 $FB devices | grep -q "$SER"; then
  $ADB reboot bootloader
  for i in $(seq 1 45); do timeout 3 $FB devices 2>/dev/null | grep -q "$SER" && break; sleep 2; done
fi
timeout 3 $FB devices | grep -q "$SER" || { log "NO-FASTBOOT"; exit 1; }
log "fastboot: unlocked=$(timeout 5 $FB getvar unlocked 2>&1 | awk '/unlocked:/{print $2}')"
timeout 120 $FB flash recovery "$IMG" || { log "FLASH-FAILED"; exit 1; }
log "flashed; rebooting to recovery"
timeout 20 $FB reboot recovery 2>&1 || timeout 20 $FB reboot-recovery 2>&1
for i in $(seq 1 90); do [ "$($ADB get-state 2>/dev/null)" = recovery ] && break; sleep 2; done
st=$($ADB get-state 2>&1); log "adb state: $st"
[ "$st" = recovery ] && echo IN-RECOVERY || echo NOT-IN-RECOVERY
