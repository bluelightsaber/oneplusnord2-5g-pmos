#!/bin/bash
# One clean Wi-Fi connection attempt with full capture: EAPOL frames (tcpdump), wpa_supplicant debug (no key
# material printed), driver log around it. Needs: pmOS up via `NOWIFI=1 pmos-ram.sh`, tcpdump on the phone.
# Driver debug: TX(0x04) RSN(0x11) SAA(0x14) QM(0x17) SEC(0x18) NIC(0x1f) at 0x3f (up to INFO) -> TX DONE status.
# Usage: eapol-test.sh OUTDIR
set -u
N=/srv/nord2-pmos; O=${1:?outdir}; mkdir -p $O; P=~/oneplusnord2-password.txt
WP=$N/firmware-vendor/private/home-wifi.nmconnection; K=~/.ssh/id_ed25519_nord2
S="ssh -i $K -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR user@172.16.42.1"
$S 'umask 077; cat > /tmp/w.nmconnection' < $WP
$S "sudo -S -p '' sh -c '
  busctl set-property fi.w1.wpa_supplicant1 /fi/w1/wpa_supplicant1 fi.w1.wpa_supplicant1 DebugLevel s debug
  for m in 0x04 0x11 0x14 0x17 0x18 0x1f; do echo \$m:0x3f > /proc/net/wlan/dbgLevel; done   # TX SEC RSN QM SAA NIC: INFO
  T0=\$(cut -d\" \" -f1 /proc/uptime); echo T0=\$T0 > /tmp/t0
  (timeout 40 tcpdump -n -e -vv -i wlan0 -l ether proto 0x888e > /tmp/eapol.txt 2>&1 &)
  sleep 2
  install -m 600 /tmp/w.nmconnection /etc/NetworkManager/system-connections/home-wifi.nmconnection; rm /tmp/w.nmconnection
  nmcli connection reload; nmcli connection up uuid \$(nmcli -g UUID,TYPE connection show | grep 802-11-wireless | cut -d: -f1 | head -1) >/dev/null 2>&1
  sleep 40
  busctl set-property fi.w1.wpa_supplicant1 /fi/w1/wpa_supplicant1 fi.w1.wpa_supplicant1 DebugLevel s info
  cat /tmp/t0 /tmp/eapol.txt > /tmp/cap-eapol.txt
  journalctl -b -u wpa_supplicant -u NetworkManager --no-pager -o short-monotonic --since -50s | grep -viE \"hexdump|PMK|PTK|KCK|KEK|psk|passphrase\" > /tmp/cap-wpa.txt
  dmesg > /tmp/cap-dmesg.txt; chmod 644 /tmp/cap-*.txt'" < $P
for f in eapol wpa dmesg; do $S "cat /tmp/cap-$f.txt" > $O/$f.txt; done
wc -l $O/*.txt
