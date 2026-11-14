#!/bin/sh
# Phase 0 diagnosis (read-only) for the OnePlus Nord 2: host + phone over adb.
N=/srv/nord2-pmos
ADB=$N/platform-tools/adb
echo "== host"; uname -r; df -h /mnt/buildhost | tail -1; python3 --version; git --version | head -1; tmux -V
echo "== lsusb"; lsusb
echo "== udev android rules"; cat /etc/udev/rules.d/51-android.rules 2>/dev/null
echo "== adb devices"; $ADB devices -l
SER=$($ADB devices | awk 'NR>1 && $2=="device"{print $1}')
echo "serials: $SER"
for s in $SER; do
  m=$($ADB -s $s shell getprop ro.product.model | tr -d '\r')
  echo "--- $s model=$m"
done
