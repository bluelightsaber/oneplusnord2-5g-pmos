#!/bin/bash
# Internet for the phone through the build host over the USB ECM link (runtime only, nothing persistent):
#   host:  one iptables MASQUERADE rule for 172.16.42.0/24 out of the uplink, tagged "nord2-usb-nat"
#          (ip_forward must already be 1; it is not changed here)
#   phone: default route via 172.16.42.2 on usb0 + DNS on usb0 (systemd-resolved)
# Usage: nat-usb.sh on|off|status
set -eu
TAG=nord2-usb-nat; NET=172.16.42.0/24; UP=$(ip route show default | awk '{print $5; exit}')
K=~/.ssh/id_ed25519_nord2; P=~/oneplusnord2-password.txt
S="ssh -i $K -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5 user@172.16.42.1"
rule() { sudo -n iptables -t nat "$1" POSTROUTING -s $NET -o $UP -m comment --comment $TAG -j MASQUERADE; }
case "${1:-status}" in
  on)  [ "$(cat /proc/sys/net/ipv4/ip_forward)" = 1 ] || { echo "ip_forward is 0 on the host: refusing"; exit 1; }
       rule -C 2>/dev/null || rule -A; echo "host: MASQUERADE $NET -> $UP"
       $S "sudo -S -p '' sh -c 'ip route replace default via 172.16.42.2 dev usb0 metric 900; resolvectl dns usb0 1.1.1.1 9.9.9.9; resolvectl domain usb0 \"~.\"'" < $P
       $S 'ip route | grep default; ping -c 2 -W 3 1.1.1.1 | tail -1; getent hosts dl-cdn.alpinelinux.org | head -1' ;;
  off) while rule -C 2>/dev/null; do rule -D; done; echo "host: rule removed"
       $S "sudo -S -p '' ip route del default via 172.16.42.2 dev usb0" < $P 2>/dev/null || true ;;
  status) sudo -n iptables -t nat -S POSTROUTING | grep $TAG || echo "host: no rule" ;;
esac
