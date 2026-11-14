#!/bin/bash
# Reboot to the bootloader (fastboot) and read variables. Writes nothing. Leaves the phone in fastboot.
N=/srv/nord2-pmos; SER=${SERIAL:?set SERIAL to the phone serial}
FB="$N/platform-tools/fastboot -s $SER"
$N/platform-tools/adb -s $SER reboot bootloader
for i in $(seq 1 45); do timeout 3 $FB devices 2>/dev/null | grep -q "$SER" && { echo "fastboot visible after ~$((i*2)) s"; break; }; sleep 2; done
lsusb | grep -iE "22d9|0e8d|18d1"
lsusb -v -d $(lsusb | awk '/22d9|0e8d|18d1/{print $6; exit}') 2>/dev/null | grep -E "bInterfaceProtocol|iInterface"
timeout 30 $FB getvar all 2>&1
