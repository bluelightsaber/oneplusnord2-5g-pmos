#!/bin/sh
# usb-role-auto (denniz): pick the USB role of the single Type-C port without Type-C detection.
# The tree has no working TCPC/role detection, so the port stays in device mode (gadget usb0 for the host PC)
# even when an OTG hub is plugged in. Policy, checked every 15 s:
#   device mode and the gadget is not configured by a host for 2 checks -> switch to host (hub, Ethernet, pendrive)
#   host mode and nothing enumerated below the root hub for 2 checks    -> switch back to device (PC cable)
# With nothing plugged in at all it alternates every ~30 s, which is harmless.
R=$(ls -d /sys/class/usb_role/*/role 2>/dev/null | head -1); U=$(ls -d /sys/class/udc/*/state 2>/dev/null | head -1)
[ -n "$R" ] || { echo "no usb_role switch"; exit 0; }
# mtu3 does not pull D+ up again after host -> device: re-bind the configfs gadget (ECM+ACM) to the UDC
to_device() { G=$(ls -d /sys/kernel/config/usb_gadget/* 2>/dev/null | head -1); [ -n "$G" ] || return 0
  echo "" > $G/UDC 2>/dev/null; sleep 1; ls /sys/class/udc | head -1 > $G/UDC; }
# images built before 2026-11-18 leave the initramfs ttyGS0 respawn loop running after switch_root; without the
# gadget it spins printing "sleep: not found" on the console (over btop): end it before any role change
for p in $(ps -eo pid,args | grep "[b]usybox sh /init$" | awk '{print $1}'); do pkill -P $p 2>/dev/null; kill $p 2>/dev/null; done
# Kernels with the MT6360 TCPC (DENNIZ_TYPEC=1): TCPM attaches us as a sink, i.e. USB device (UFP). A PC then
# configures the gadget. If nobody does while a partner is attached, it is a hub: re-bind the gadget once (mtu3
# misses the D+ pull-up after a role change), then ask for a PD data-role swap to host; if the partner cannot
# swap (no PD), force host on the controller as on kernels without a TCPC.
sleep 20
P=/sys/class/typec/port0
if [ -d $P ]; then
  logger -t usb-role-auto "Type-C port present: TCPM mode"
  n=0
  while true; do
    if [ -d /sys/class/typec/port0-partner ] && grep -q '\[device\]' $P/data_role && [ "$(cat $R)" != host ]; then
      case "$(cat $U 2>/dev/null)" in configured|suspended) n=0;; *) n=$((n+1));; esac
      if [ $n = 2 ]; then to_device; logger -t usb-role-auto "partner, gadget idle: gadget re-bound"
      elif [ $n -ge 4 ]; then
        if echo host > $P/data_role 2>/dev/null; then logger -t usb-role-auto "partner, gadget idle: DR_Swap -> host"
        else echo host > $R; logger -t usb-role-auto "partner, gadget idle, no DR_Swap: forced host"; fi
        n=0
      fi
    else n=0; fi
    sleep 5
  done
fi
n=0
while true; do
  role=$(cat $R)
  if [ "$role" = device ]; then
    st=$(cat $U 2>/dev/null)
    case "$st" in configured|suspended) n=0;; *) n=$((n+1));; esac
    [ $n -ge 2 ] && { echo host > $R; logger -t usb-role-auto "gadget $st -> host"; n=0; sleep 15; }
  else
    devs=$(ls /sys/bus/usb/devices 2>/dev/null | grep -cE '^[0-9]+-[0-9.]+$')   # real devices, not the root hub's 1-0:1.0
    [ "$devs" -gt 0 ] && n=0 || n=$((n+1))
    [ $n -ge 2 ] && { echo device > $R; to_device; logger -t usb-role-auto "no USB devices -> device"; n=0; sleep 15; }
  fi
  sleep 15
done
