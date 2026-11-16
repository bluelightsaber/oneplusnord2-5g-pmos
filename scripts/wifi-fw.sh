#!/bin/bash
# Collect the connectivity (Wi-Fi/BT) firmware for the MT6893 CONNAC2 "soc3_0" driver from the phone's OWN
# partition backup, read-only (debugfs, nothing mounted, nothing written to the phone):
#   vendor (from super, via lpinfo.py): /firmware/{soc3_0_*,WIFI_RAM_CODE_soc3_0_*,conninfra.cfg}, wifi_<prj>.cfg
#   nvdata: /APCFG/APRDEB/WIFI + BT_Addr (per-device calibration + MAC -> PRIVATE, never publish)
# Output: $N/firmware-vendor/<build>/wifi-fw.tgz with usr/lib/firmware/... (unpacked into the rootfs by pmos-ram.sh).
# NOT lib/...: pmOS has /lib -> usr/lib and busybox tar replaces that symlink with a directory (breaks /sbin/init).
# Usage: wifi-fw.sh [BACKUP_DIR] [PRJ=20831]
set -euo pipefail
N=/srv/nord2-pmos; B=${1:-$N/backups/partitions/oos11-A20-20261114-1932}; PRJ=${2:-20831}
F=$N/firmware-vendor/oos11-A20; mkdir -p $F; chmod 700 $F
[ -f $F/vendor.img ] || python3 $N/repo/scripts/lpinfo.py $B/super.img vendor $F/vendor.img
S=$(mktemp -d); trap "rm -rf $S" EXIT; L=$S/usr/lib/firmware; mkdir -p $L/mediatek/mt6893
dbg() { /usr/sbin/debugfs -R "$1" "$2" 2>/dev/null; }
for f in $(dbg "ls -p /firmware" $F/vendor.img | awk -F/ '{print $6}' | grep -E '^(soc3_0_|WIFI_RAM_CODE_soc3_0|conninfra\.cfg$)'); do
  dbg "dump /firmware/$f $L/$f" $F/vendor.img; done
dbg "dump /firmware/wifi_$PRJ.cfg $L/wifi.cfg" $F/vendor.img
# denniz mainline: keep the firmware awake (CAM). With power save, after a disconnect/idle period the firmware
# stopped answering (empty scans, scan timeout -> chip reset that never completes).
printf '\n# denniz mainline\nPowerSave 0\n' >> $L/wifi.cfg
dbg "dump /APCFG/APRDEB/WIFI $L/mediatek/mt6893/WIFI" $B/nvdata.img
dbg "dump /APCFG/APRDEB/BT_Addr $L/mediatek/mt6893/BT_Addr" $B/nvdata.img
chmod -R u=rwX,go=rX $S/usr
ls -la $L $L/mediatek/mt6893 | awk '{print $5, $9}' | grep -v "^ *$"
[ -s $L/mediatek/mt6893/WIFI ] && [ -n "$(ls $L/soc3_0_ram_wifi_* 2>/dev/null)" ] || { echo "missing files"; exit 1; }
tar -C $S --owner=0 --group=0 -czf $F/wifi-fw.tgz usr; chmod 600 $F/wifi-fw.tgz; ls -la $F/wifi-fw.tgz
