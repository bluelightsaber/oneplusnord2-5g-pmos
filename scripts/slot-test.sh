#!/bin/bash
# Recovery-slot test cycle (writes the `recovery` partition: needs FLASH_RECOVERY=1, user-approved).
#   Android (adb) -> bootloader -> fastboot flash recovery IMG -> fastboot reboot recovery -> watch USB.
#   Success = our initramfs gadget 18d1:d001 appears: run acm-run.sh (logs) and leave it up (or REBOOT=1).
#   Failure = Android comes back (panic=5 / safety timer / LK fallback): read expdb later (expdb-from-twrp.sh).
# Usage: FLASH_RECOVERY=1 slot-test.sh IMG [WAIT_s=240]
set -u
N=/srv/nord2-pmos; PT=$N/platform-tools; SER=${SERIAL:?set SERIAL to the phone serial}
IMG=$1; WAIT=${2:-240}; NAME=$(basename $IMG .img)
[ "${FLASH_RECOVERY:-0}" = 1 ] || { echo "refusing: set FLASH_RECOVERY=1 (writes the recovery partition)"; exit 1; }
sha256sum -c $IMG.sha256 >/dev/null || { echo "sha256 mismatch for $IMG"; exit 1; }
O=$N/tests/slot/$NAME-$(date +%Y%m%d-%H%M%S); mkdir -p $O
log() { echo "$(date +%T) $*" | tee -a $O/cycle.log; }
usbid() { lsusb | grep -oE "ID (22d9|0e8d|18d1|0525):[0-9a-f]{4}" | head -1; }
log "image $IMG ($(cut -c1-16 $IMG.sha256)) usb=$(usbid)"
if ! $PT/fastboot devices | grep -q $SER; then
  case "$($PT/adb -s $SER get-state 2>/dev/null)" in device|recovery) ;; *) log "phone not in adb (Android/TWRP) nor fastboot"; exit 1;; esac
  $PT/adb -s $SER reboot bootloader </dev/null
  for i in $(seq 60); do $PT/fastboot devices | grep -q $SER && break; sleep 2; done
fi
$PT/fastboot devices | grep -q $SER || { log "no fastboot"; exit 1; }
log "fastboot up; flashing recovery"
$PT/fastboot -s $SER flash recovery $IMG 2>&1 | tee -a $O/cycle.log | grep -q "Finished" || { log "flash failed"; exit 1; }
$PT/fastboot -s $SER reboot recovery 2>&1 | tee -a $O/cycle.log
log "rebooting into recovery slot; watching USB for ${WAIT}s"
end=$((SECONDS + WAIT)); last=""
while [ $SECONDS -lt $end ]; do
  u=$(usbid); [ "$u" != "$last" ] && { log "usb: ${u:-none}"; last=$u; }
  case "$u" in
    "ID 0525:a4a7") log "kernel legacy g_serial gadget (no configfs gadget): shell on ttyACM";;
    "ID 18d1:d001") log "OUR INITRAMFS IS UP"; sleep 3; $N/repo/scripts/acm-run.sh $O; [ "${REBOOT:-0}" = 1 ] && echo "reboot -f" | $N/repo/scripts/acm-run.sh $O cmd; log "done"; exit 0;;
  esac
  $PT/adb -s $SER get-state 2>/dev/null | grep -q device && { log "Android is back: test image did not reach the gadget"; exit 2; }
  sleep 2
done
log "timeout: nothing recognised on USB (hung? watchdog/safety timer should reboot it)"; exit 3
