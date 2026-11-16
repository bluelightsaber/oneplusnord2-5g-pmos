#!/bin/bash
# Reboot the phone from pmOS RAM back to Android, wait for full boot, then RAM-boot IMG via pmos-ram.sh.
N=/srv/nord2-pmos; PT=$N/platform-tools; SER=${SERIAL:?set SERIAL to the phone serial}; IMG=$1
ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -i ~/.ssh/id_ed25519_nord2 user@172.16.42.1 "sudo -S -p '' systemctl reboot" < ~/oneplusnord2-password.txt || echo "ssh reboot failed (maybe already down)"
for i in $(seq 120); do [ "$($PT/adb -s $SER shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && break; sleep 3; done
[ "$($PT/adb -s $SER shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] || { echo "Android not up"; exit 1; }
echo "Android up"; sleep 15
bash $N/repo/scripts/pmos-ram.sh $IMG
