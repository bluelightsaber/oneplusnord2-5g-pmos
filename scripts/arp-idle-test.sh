#!/bin/bash
# arp-idle-test.sh IP [MINUTES=60] [STEP=5]: from the host, every STEP minutes drop the neighbour entry for IP and
# send one ping (forces a fresh ARP). Detects a phone that stops answering broadcast ARP after idle periods.
# Needs sudo for "ip neigh del" (falls back to waiting for the entry to expire). Output: one line per probe.
IP=$1; M=${2:-60}; S=${3:-5}
for i in $(seq 0 $S $M); do
  sudo -n ip neigh del $IP dev enp3s0 2>/dev/null
  t0=$(date +%s.%N); if ping -c1 -W3 $IP >/dev/null 2>&1; then r=ok; else r=FAIL; fi
  echo "$(date +%H:%M:%S) +${i}min ping=$r $(awk "BEGIN{printf \"%.0f ms\", ($(date +%s.%N)-$t0)*1000}") $(ip neigh show $IP | awk '{print $NF}')"
  sleep $((S*60))
done
