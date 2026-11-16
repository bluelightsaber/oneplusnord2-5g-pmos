#!/bin/bash
# Experiment: after a clean RAM boot, program the (unprogrammed) host WFDMA1 TX ring 2 = "priority data" ring
# (base 0xBE008000 = rTxDesc[2] in wifi-reserve-memory, 1024 entries) with devmem2 before connecting, then
# test unicast on the open network. Usage: ring2-test.sh "SSID" OUTDIR
set -u
SSID=${1:?ssid}; O=${2:?outdir}; mkdir -p $O; P=~/oneplusnord2-password.txt; K=~/.ssh/id_ed25519_nord2
S="ssh -i $K -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR user@172.16.42.1"
N=/srv/nord2-pmos
bash $N/repo/scripts/nat-usb.sh on > /dev/null 2>&1
$S "cat > /tmp/wd.sh" < ~/wfdma-devmem.sh
$S "sudo -S -p '' sh -c '
  apk add -q devmem2 2>&1 | grep -v WARNING
  ip link set wlan0 up; nmcli device wifi rescan >/dev/null 2>&1; sleep 6
  sh /tmp/wd.sh > /tmp/r2.regs.txt
  devmem2 0x18025320 w 0xBE008000 >/dev/null; devmem2 0x18025324 w 0x400 >/dev/null
  devmem2 0x18025328 w 0 >/dev/null
  sh /tmp/wd.sh | sed -n 14p >> /tmp/r2.regs.txt
  nmcli connection delete open-test >/dev/null 2>&1
  nmcli connection add type wifi ifname wlan0 con-name open-test ssid \"$SSID\" ipv6.method disabled >/dev/null
  timeout 40 nmcli connection up open-test > /tmp/r2.nm.txt 2>&1
  ip -br addr show wlan0 >> /tmp/r2.nm.txt
  GW=\$(ip route show dev wlan0 | sed -n \"s/^default via \\([0-9.]*\\).*/\\1/p\")
  ping -I wlan0 -c 10 \$GW > /tmp/r2.ping.txt 2>&1; ping -I wlan0 -c 5 1.1.1.1 >> /tmp/r2.ping.txt 2>&1
  echo == after >> /tmp/r2.regs.txt; sh /tmp/wd.sh >> /tmp/r2.regs.txt
  dmesg > /tmp/r2.dmesg.txt; chmod 644 /tmp/r2.*'" < $P
for f in nm.txt ping.txt regs.txt dmesg.txt; do $S "cat /tmp/r2.$f" > $O/r2.$f; done
cat $O/r2.nm.txt; grep -E "packets|bytes from" $O/r2.ping.txt | head -6; grep -E "^== |TX(0|2|17) " $O/r2.regs.txt
