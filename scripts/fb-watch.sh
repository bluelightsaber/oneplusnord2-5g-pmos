#!/bin/sh
# Reboot to bootloader and log every USB identity the phone presents for 90 s.
N=/srv/nord2-pmos
$N/platform-tools/adb -s <SERIAL> reboot bootloader
last=""
for i in $(seq 1 90); do
  cur=$(lsusb | grep -viE "1d6b|0bda:5520|8087|152d" | sed 's/Device [0-9]*//')
  [ "$cur" != "$last" ] && { echo "t=${i}s: ${cur:-<nothing>}"; last="$cur"; }
  if echo "$cur" | grep -q . ; then
    timeout 2 $N/platform-tools/fastboot devices 2>/dev/null | sed "s/^/  fastboot t=${i}s: /"
  fi
  sleep 1
done
