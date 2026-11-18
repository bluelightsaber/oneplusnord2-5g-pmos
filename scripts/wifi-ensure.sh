#!/bin/sh
# wifi-ensure: recover the MTK gen4m Wi-Fi when its TX path hangs (WFDMA1 TX0 ring full, "Tx timeout", gateway
# ARP INCOMPLETE while still associated; seen 2026-11-17 after ~1 h). Every INTERVAL s ping the default gateway
# of wlan0; after FAILS consecutive misses power-cycle the chip through WMT (/dev/wmtWifi 0 -> 1) and let
# NetworkManager reconnect. Manual equivalent: nmcli radio wifi off; echo 0 > /dev/wmtWifi; echo 1 > /dev/wmtWifi;
# nmcli radio wifi on. Installed as /usr/local/sbin/wifi-ensure (wifi-ensure.service).
INTERVAL=30; FAILS=3; n=0
while true; do
  sleep $INTERVAL
  gw=$(ip -4 route show default dev wlan0 2>/dev/null | awk '{print $3; exit}')
  if [ -z "$gw" ]; then n=0; continue; fi       # not connected: NetworkManager's job
  if ping -c2 -W3 -I wlan0 "$gw" >/dev/null 2>&1; then n=0; continue; fi
  n=$((n + 1)); [ $n -lt $FAILS ] && continue
  logger -t wifi-ensure "gateway $gw unreachable ${FAILS}x: power-cycling Wi-Fi"
  nmcli radio wifi off; sleep 2
  [ -e /dev/wmtWifi ] && { echo 0 > /dev/wmtWifi; sleep 3; echo 1 > /dev/wmtWifi; sleep 5; }
  nmcli radio wifi on; n=0; sleep 60
done
