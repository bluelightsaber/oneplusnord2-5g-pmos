#!/bin/bash
# Reboot to fastbootd (userspace fastboot in recovery), read variables, reboot to Android. Writes nothing.
N=/srv/nord2-pmos; SER=${SERIAL:?set SERIAL to the phone serial}
FB="$N/platform-tools/fastboot -s $SER"
$N/platform-tools/adb -s $SER reboot fastboot
for i in $(seq 1 60); do timeout 2 $FB devices 2>/dev/null | grep -q "$SER" && { echo "fastboot visible at ${i}"; break; }; sleep 2; done
lsusb | grep 22d9
timeout 30 $FB getvar all 2>&1 | grep -vE "partition-(size|type)|is-logical" 
timeout 10 $FB getvar unlocked 2>&1
timeout 20 $FB reboot 2>&1
