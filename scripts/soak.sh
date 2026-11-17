#!/bin/bash
# soak.sh (buildhost): log the phone's health every 5 min over Wi-Fi (fallback USB) to $N/tests/soak/soak-<date>.txt
N=/srv/nord2-pmos; mkdir -p $N/tests/soak; L=$N/tests/soak/soak-$(date +%Y%m%d-%H%M).txt
K="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10 -i $HOME/.ssh/id_ed25519_nord2"
W=192.168.1.42; echo "# soak start $(date -Is)" >> $L
while :; do
  p=$(ping -c 3 -W 2 -q $W 2>/dev/null | grep -oE "[0-9]+ received" | cut -d' ' -f1)
  a=$(ping -c 1 -W 2 -q $W >/dev/null 2>&1 && echo ok || echo FAIL)
  o=$(ssh $K user@$W 'echo "up=$(cut -d. -f1 /proc/uptime)s load=$(cut -d" " -f1-3 /proc/loadavg) mem=$(free -m | awk "/Mem/{print \$3}")M \
bat=$(cat /sys/class/power_supply/bq28z610-0/capacity 2>/dev/null)% st=$(cat /sys/class/power_supply/bq28z610-0/status 2>/dev/null) \
tmax=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -n | tail -1) \
svc=$(systemctl is-active docker tailscaled NetworkManager charge-limit | tr "\n" ,) sys=$(systemctl is-system-running) \
kern=$(uname -r)"' 2>/dev/null || echo "ssh-wifi FAIL")
  echo "$(date +%H:%M) ping=${p:-0}/3 arp=$a $o" >> $L
  sleep 300
done
