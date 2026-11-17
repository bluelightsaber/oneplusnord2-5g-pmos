#!/bin/sh
# usb-mode.sh: USB data role of the denniz port (mtu3 role switch; no Type-C controller driver).
#   usb-mode.sh status         current role
#   usb-mode.sh host|device    switch now
#   usb-mode.sh try SECS       host for SECS seconds, then back to device unless /run/usb-host-keep exists
#                              (touch it over Wi-Fi once the hub works). Runs detached; safe to start over ssh.
# Host mode never drives VBUS (no vbus-supply in the DT): use a POWERED hub. Device mode = USB gadget (SSH 172.16.42.1).
set -e
R=$(ls -d /sys/class/usb_role/*usb* 2>/dev/null | head -1)
[ -n "$R" ] || { echo "no usb_role switch (old kernel/DT?)"; exit 1; }
log() { echo "usb-mode: $*"; logger -t usb-mode "$*" 2>/dev/null || true; }
# Back to device: the configfs gadget stays "not attached" after a host->device switch until it is re-bound
# (seen 2026-11-16), so rebind every gadget to the UDC.
to_device() {
  echo device > $R/role; sleep 1
  for g in /sys/kernel/config/usb_gadget/*/UDC; do
    [ -e "$g" ] || continue; u=$(ls /sys/class/udc | head -1)
    echo "" > $g 2>/dev/null || true; sleep 1; echo $u > $g
  done
}
case "$1" in
  status) cat $R/role ;;
  host) echo host > $R/role; log "role -> host" ;;
  device) to_device; log "role -> device" ;;
  try)
    S=${2:-300}; rm -f /run/usb-host-keep
    echo host > $R/role; log "role -> host for $S s (keep with: touch /run/usb-host-keep)"
    # transient systemd timer: must survive the ssh session that started it (a background subshell is killed)
    systemctl stop usb-mode-fallback.timer 2>/dev/null || true
    systemd-run -q --unit=usb-mode-fallback --on-active=${S}s /usr/local/sbin/usb-mode _fallback 0
    ;;
  _fallback) sleep $2; if [ -e /run/usb-host-keep ]; then log "kept host"; else to_device; log "fallback -> device"; fi ;;
  *) sed -n '2,8p' $0; exit 2 ;;
esac
