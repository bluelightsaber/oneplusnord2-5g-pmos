#!/bin/bash
# Wi-Fi data-path stall probe: connect to an open network with quiet driver logs, dump the host WFDMA
# registers (via the driver's /proc/net/wlan/mcr) before and after pinging the gateway, and sample the
# Wi-Fi IRQ counters. TX/cmd/event rings live on HOST WFDMA1 (0x7c025000), RX data on WFDMA0 (0x7c024000).
# Needs pmOS up without the saved WPA profile (NOWIFI=1 pmos-ram.sh). Usage: wifi-irq-test.sh "SSID" OUTDIR
set -u
SSID=${1:?ssid}; O=${2:?outdir}; mkdir -p $O; P=~/oneplusnord2-password.txt; K=~/.ssh/id_ed25519_nord2
S="ssh -i $K -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR user@172.16.42.1"
cat > $O/regs.sh <<'R'
# name base offsets...  ring CTRL0..3 = base(lo), cnt, cidx, didx
dump() { for a in "$@"; do echo $a > /proc/net/wlan/mcr; printf "%s " "$(cat /proc/net/wlan/mcr | tr -s ' \n' ' ')"; done; echo; }
echo "== $1 $(date +%T)"
for b in 0x7c024 0x7c025; do
  echo "DMA ${b}000 INT_STA/MASK/GLO_CFG:"; dump ${b}200 ${b}204 ${b}208
  for r in 0 1 2 16 17; do o=$(printf "%x" $((0x300 + r*16))); echo -n "TX$r: "; dump ${b}$o ${b}$(printf "%x" $((0x$o+4))) ${b}$(printf "%x" $((0x$o+8))) ${b}$(printf "%x" $((0x$o+12))); done
  for r in 0 1 2 3; do o=$(printf "%x" $((0x500 + r*16))); echo -n "RX$r: "; dump ${b}$o ${b}$(printf "%x" $((0x$o+4))) ${b}$(printf "%x" $((0x$o+8))) ${b}$(printf "%x" $((0x$o+12))); done
done
grep -E "wlan" /proc/interrupts
R
$S 'cat > /tmp/regs.sh' < $O/regs.sh
$S "sudo -S -p '' sh -c '
  nmcli connection delete open-test >/dev/null 2>&1
  nmcli connection add type wifi ifname wlan0 con-name open-test ssid \"$SSID\" ipv6.method disabled >/dev/null
  timeout 40 nmcli connection up open-test > /tmp/irq.nm.txt 2>&1
  ip -br addr show wlan0 >> /tmp/irq.nm.txt; GW=\$(ip route show dev wlan0 | sed -n \"s/^default via \\([0-9.]*\\).*/\\1/p\"); echo GW=\$GW >> /tmp/irq.nm.txt
  sh /tmp/regs.sh connected > /tmp/irq.regs.txt 2>&1
  ping -I wlan0 -c 10 \$GW > /tmp/irq.ping.txt 2>&1
  sh /tmp/regs.sh after-ping >> /tmp/irq.regs.txt 2>&1
  sleep 5; sh /tmp/regs.sh plus5s >> /tmp/irq.regs.txt 2>&1
  dmesg > /tmp/irq.dmesg.txt; chmod 644 /tmp/irq.*'" < $P
for f in nm.txt ping.txt regs.txt dmesg.txt; do $S "cat /tmp/irq.$f" > $O/irq.$f; done
cat $O/irq.nm.txt; tail -3 $O/irq.ping.txt; cat $O/irq.regs.txt
grep kalDumpHifStats $O/irq.dmesg.txt | tail -4 | cut -c1-200
