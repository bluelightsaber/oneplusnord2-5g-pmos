#!/bin/bash
# Talk to the denniz initramfs root shell on the USB ACM port (needs sudo for /dev/ttyACM*).
#   acm-run.sh OUTDIR        -> standard diagnostics into OUTDIR/initramfs-*.txt (also touches /tmp/keep)
#   echo CMD | acm-run.sh OUTDIR cmd   -> run one command, print its output
set -u
O=$1; MODE=${2:-diag}; mkdir -p $O
TTY=""; for i in $(seq 20); do TTY=$(ls /dev/ttyACM* 2>/dev/null | head -1); [ -n "$TTY" ] && break; sleep 1; done
[ -n "$TTY" ] || { echo "no /dev/ttyACM*"; exit 1; }
sudo -n stty -F $TTY raw -echo 115200
run() { # $1 = command, $2 = timeout s
  local m="__END_${RANDOM}__"
  sudo -n timeout $2 sh -c "cat $TTY" > /tmp/acm.$$ & local c=$!
  sleep 0.5; printf '%s; echo %s\n' "$1" "$m" | sudo -n tee $TTY >/dev/null
  for i in $(seq $(( $2 * 2 ))); do grep -q "$m" /tmp/acm.$$ && break; sleep 0.5; done
  sudo -n kill $c 2>/dev/null; wait $c 2>/dev/null; sed "/$m/d" /tmp/acm.$$ | tr -d '\r'; rm -f /tmp/acm.$$
}
if [ "$MODE" = cmd ]; then read -r C; run "$C" 30; exit 0; fi
run "touch /tmp/keep" 5 >/dev/null
run "uname -a; cat /proc/cmdline; uptime; cat /proc/meminfo | head -3" 10 > $O/initramfs-basic.txt
run "dmesg" 30 > $O/initramfs-dmesg.txt
run "cat /proc/partitions; ls /sys/class/udc /sys/class/net /sys/class/scsi_disk 2>&1" 10 > $O/initramfs-hw.txt
run "cat /sys/kernel/debug/devices_deferred 2>/dev/null; ls /sys/bus/platform/drivers" 10 > $O/initramfs-drivers.txt
wc -l $O/initramfs-*.txt; head -5 $O/initramfs-basic.txt
