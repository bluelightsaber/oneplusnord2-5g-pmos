#!/bin/sh
# wifi-ensure: recover the MTK gen4m Wi-Fi when its TX path hangs (WFDMA1 TX0 ring full, gateway ARP INCOMPLETE
# while still associated). Seen 2026-11-17 after ~1 h, 2026-11-18 after 56 min of load and 5 min after boot idle.
# Every INTERVAL s ping the default gateway of wlan0; after FAILS consecutive misses dump diagnostics to the
# journal (WFDMA0/1 rings twice 1 s apart, link, station) and power-cycle the radio (NetworkManager radio off/on
# powers the chip down/up; the WMT write is a fallback), then let NetworkManager reconnect.
# Note: "halCheckHifState: Tx timeout" every second is NOT the hang by itself: a leaked MSDU token keeps it firing
# while traffic flows; the gateway ping is the real test. Diagnostics: journalctl -t wifi-ensure.
INTERVAL=10; FAILS=3; n=0
r() { devmem2 $(printf 0x%x $1) w 2>/dev/null | sed -n 's/.*: \(0x[0-9A-Fa-f]*\)$/\1/p'; }
dump() {   # host WFDMA0 (RX data) / WFDMA1 (TX data, cmd, events): base cnt cidx didx per ring
  for b in $((0x18024000)) $((0x18025000)); do
    l="$(printf 0x%x $b) sta/mask/glo $(r $((b+0x200))) $(r $((b+0x204))) $(r $((b+0x208)))"
    for t in 0 1 2 16 17; do o=$((b+0x300+t*16)); l="$l | TX$t $(r $o) $(r $((o+4))) $(r $((o+8))) $(r $((o+12)))"; done
    for x in 0 1 2 3; do o=$((b+0x500+x*16)); l="$l | RX$x $(r $o) $(r $((o+4))) $(r $((o+8))) $(r $((o+12)))"; done
    logger -t wifi-ensure "wfdma $l"
  done
}
while true; do
  sleep $INTERVAL
  gw=$(ip -4 route show default dev wlan0 2>/dev/null | awk '{print $3; exit}')
  if [ -z "$gw" ]; then n=0; continue; fi       # not connected: NetworkManager's job
  if ping -c2 -W2 -I wlan0 "$gw" >/dev/null 2>&1; then n=0; continue; fi
  n=$((n + 1)); [ $n -lt $FAILS ] && continue
  logger -t wifi-ensure "gateway $gw unreachable ${FAILS}x: dumping state, power-cycling Wi-Fi"
  command -v devmem2 >/dev/null && { dump; sleep 1; dump; }
  logger -t wifi-ensure "link: $(iw dev wlan0 link 2>&1 | tr '\n\t' '  ' | sed 's/[0-9a-f:]\{17\}/<bssid>/g')"
  logger -t wifi-ensure "neigh: $(ip neigh show dev wlan0 | grep -c INCOMPLETE) incomplete; $(grep wlan0 /proc/net/dev | awk '{print "rx "$2" tx "$10" txerr "$12" txdrop "$13}')"
  nmcli radio wifi off; sleep 2
  [ -e /dev/wmtWifi ] && { echo 0 > /dev/wmtWifi; sleep 3; echo 1 > /dev/wmtWifi; sleep 5; }
  nmcli radio wifi on; n=0; sleep 60
  logger -t wifi-ensure "after power cycle: $(nmcli -t -f DEVICE,STATE dev | grep '^wlan0:')"
done
