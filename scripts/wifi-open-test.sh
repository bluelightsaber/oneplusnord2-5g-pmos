#!/bin/bash
# Wi-Fi data-path test on an OPEN network (no WPA): does DHCP/data TX work at all? Full driver logging for
# TX(0x04) QM(0x17) NIC(0x1f) HAL(0x01) RSN(0x11) at 0xff, tcpdump of DHCP/ARP/EAPOL on wlan0.
# Needs pmOS up (NOWIFI=1 pmos-ram.sh) and tcpdump on the phone. Usage: wifi-open-test.sh "SSID" OUTDIR
set -u
SSID=${1:?ssid}; O=${2:?outdir}; mkdir -p $O; P=~/oneplusnord2-password.txt; K=~/.ssh/id_ed25519_nord2
S="ssh -i $K -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR user@172.16.42.1"
$S "sudo -S -p '' sh -c '
  for m in 0x01 0x04 0x11 0x17 0x1f; do echo \$m:0xff > /proc/net/wlan/dbgLevel; done
  (timeout 45 tcpdump -n -e -i wlan0 -l \"port 67 or port 68 or arp or ether proto 0x888e\" > /tmp/open.pcap.txt 2>&1 &)
  sleep 2
  nmcli connection delete open-test >/dev/null 2>&1
  nmcli connection add type wifi ifname wlan0 con-name open-test ssid \"$SSID\" ipv6.method disabled >/dev/null
  timeout 40 nmcli connection up open-test > /tmp/open.nm.txt 2>&1
  sleep 4; ip -br addr show wlan0 >> /tmp/open.nm.txt; ip route >> /tmp/open.nm.txt
  for m in 0x01 0x04 0x11 0x17 0x1f; do echo \$m:0x03 > /proc/net/wlan/dbgLevel; done
  journalctl -b -u wpa_supplicant -u NetworkManager --no-pager -o short-monotonic --since -60s > /tmp/open.wpa.txt
  dmesg > /tmp/open.dmesg.txt; chmod 644 /tmp/open.*'" < $P
for f in pcap.txt nm.txt wpa.txt dmesg.txt; do $S "cat /tmp/open.$f" > $O/$f; done
wc -l $O/*; cat $O/nm.txt; cat $O/pcap.txt | head -20
