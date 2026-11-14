#!/bin/sh
# Phase 0 phone diagnosis (read-only, adb shell as the unprivileged shell user).
N=/srv/nord2-pmos
SER=${SERIAL:?set SERIAL to the phone serial}
A="$N/platform-tools/adb -s $SER"
echo "== props"
for p in ro.product.model ro.product.device ro.product.name ro.product.board ro.board.platform \
  ro.hardware ro.build.display.id ro.build.version.release ro.build.version.security_patch \
  ro.build.fingerprint ro.boot.slot_suffix ro.build.ab_update ro.boot.dynamic_partitions \
  ro.virtual_ab.enabled ro.boot.flash.locked ro.boot.verifiedbootstate ro.boot.vbmeta.device_state \
  ro.oem_unlock_supported sys.oem_unlock_allowed ro.product.first_api_level ro.bootloader \
  ro.boot.hardware.revision ro.vendor.oplus.market.name ro.build.product ro.product.vendor.device \
  ro.soc.model ro.soc.manufacturer ro.boot.serialno ro.treble.enabled ro.kernel.version; do
  printf '%s=%s\n' "$p" "$($A shell getprop $p | tr -d '\r')"
done
echo "== kernel"; $A shell uname -a
echo "== cpu/mem"; $A shell 'cat /proc/cpuinfo | grep -E "Hardware|CPU part" | sort | uniq -c; grep -E "MemTotal" /proc/meminfo'
echo "== block by-name"; $A shell 'ls -l /dev/block/by-name/ 2>&1 | awk "{print \$(NF-2), \$NF}"' 2>&1 | head -150
echo "== partitions sizes"; $A shell 'cat /proc/partitions' 2>&1 | head -120
echo "== storage"; $A shell 'df -h /data 2>&1 | tail -1'
echo "== battery"; $A shell dumpsys battery
echo "== power_supply"; $A shell 'for d in /sys/class/power_supply/*; do echo "-- $d"; for f in type status capacity health charge_full charge_full_design cycle_count voltage_now temp current_now; do [ -r $d/$f ] && echo "$f=$(cat $d/$f 2>/dev/null)"; done; done' 2>&1 | head -80
echo "== usb"; $A shell 'getprop sys.usb.config; getprop sys.usb.state'
