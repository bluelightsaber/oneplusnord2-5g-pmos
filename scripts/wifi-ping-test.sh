#!/bin/bash
# Wi-Fi unicast check: connect a NetworkManager profile (open SSID, or an existing profile with PROFILE=name),
# ping gateway and 1.1.1.1 over wlan0, dump the host WFDMA rings (devmem2, via NAT) and dmesg.
# Usage: [PROFILE=name] wifi-ping-test.sh "SSID" OUTDIR
set -u
SSID=${1:?ssid}; O=${2:?outdir}; mkdir -p $O; P=~/oneplusnord2-password.txt; K=~/.ssh/id_ed25519_nord2
S="ssh -i $K -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR user@172.16.42.1"
N=/srv/nord2-pmos; PROF=${PROFILE:-open-test}
bash $N/repo/scripts/nat-usb.sh on > /dev/null 2>&1
$S "cat > /tmp/wd.sh" < ~/wfdma-devmem.sh
$S "sudo -S -p '' sh -c '
  apk add -q devmem2 2>&1 | grep -v WARNING
  if [ \"$PROF\" = open-test ]; then nmcli connection delete open-test >/dev/null 2>&1
    nmcli connection add type wifi ifname wlan0 con-name open-test ssid \"$SSID\" ipv6.method disabled >/dev/null; fi
  timeout 60 nmcli connection up \"$PROF\" > /tmp/pt.nm.txt 2>&1
  sleep 3; ip -br addr show wlan0 >> /tmp/pt.nm.txt
  GW=\$(ip route show dev wlan0 | sed -n \"s/^default via \\([0-9.]*\\).*/\\1/p\"); echo GW=\$GW >> /tmp/pt.nm.txt
  ping -I wlan0 -c 10 \$GW > /tmp/pt.ping.txt 2>&1; ping -I wlan0 -c 5 1.1.1.1 >> /tmp/pt.ping.txt 2>&1
  sh /tmp/wd.sh > /tmp/pt.regs.txt; dmesg > /tmp/pt.dmesg.txt; chmod 644 /tmp/pt.*'" < $P
for f in nm.txt ping.txt regs.txt dmesg.txt; do $S "cat /tmp/pt.$f" > $O/pt.$f; done
cat $O/pt.nm.txt; grep -E "packets|bytes from" $O/pt.ping.txt | head -8; grep -E "^== 0x18025|TX(0|1|2|17) " $O/pt.regs.txt | tail -5
grep -E "glResetTrigger|Trigger chip reset" $O/pt.dmesg.txt | head -3
