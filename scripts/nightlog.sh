#!/bin/sh
# Overnight log on the phone: every 60 s battery (capacity %, mV, mA, 0.1 C, status) + one ping to the gateway
# over wlan0 + wlan0 state. Output CSV: /var/tmp/nightlog.csv
B=/sys/class/power_supply/bq28z610-0
echo "time,cap,uv,ua,temp,status,ping_ms,wlan" >> /var/tmp/nightlog.csv
while true; do
  p=$(ping -I wlan0 -c 1 -W 3 192.168.1.1 2>/dev/null | sed -n 's/.*time=\([0-9.]*\).*/\1/p')
  w=$(cat /sys/class/net/wlan0/operstate 2>/dev/null)
  echo "$(date +%FT%T),$(cat $B/capacity),$(cat $B/voltage_now),$(cat $B/current_now),$(cat $B/temp),$(cat $B/status),${p:-LOST},$w" >> /var/tmp/nightlog.csv
  sleep 60
done
