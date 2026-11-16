#!/bin/bash
# Run by the USER (interactive): asks for the Wi-Fi passphrase without echo and creates a NetworkManager profile
# on the phone (root-only keyfile), then brings it up. The passphrase travels over ssh stdin only (not argv, not
# logs). A copy of the profile is kept PRIVATE on the build host ($N/firmware-vendor/private/, mode 600, never
# published) so pmos-ram.sh can install it on every RAM boot. Usage: wifi-connect.sh "SSID"
set -eu
SSID=${1:?usage: wifi-connect.sh SSID}
K=~/.ssh/id_ed25519_nord2; P=~/oneplusnord2-password.txt
S="ssh -i $K -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR user@172.16.42.1"
read -r -s -p "Wi-Fi passphrase for '$SSID': " PSK; echo
UUID=$(cat /proc/sys/kernel/random/uuid)
V=/srv/nord2-pmos/firmware-vendor/private; mkdir -p $V; chmod 700 $V; umask 077
printf '[connection]\nid=%s\nuuid=%s\ntype=wifi\ninterface-name=wlan0\nautoconnect=true\n\n[wifi]\nmode=infrastructure\nssid=%s\n\n[wifi-security]\nkey-mgmt=wpa-psk\npsk=%s\n\n[ipv4]\nmethod=auto\n\n[ipv6]\nmethod=auto\n' \
  "$SSID" "$UUID" "$SSID" "$PSK" > $V/home-wifi.nmconnection
$S 'umask 077; cat > /tmp/home-wifi.nmconnection' < $V/home-wifi.nmconnection
C=/etc/NetworkManager/system-connections/home-wifi.nmconnection
$S "sudo -S -p '' sh -c 'install -m 600 -o root -g root /tmp/home-wifi.nmconnection $C && rm /tmp/home-wifi.nmconnection && nmcli connection reload && nmcli connection up uuid $UUID'" < $P
unset PSK
sleep 3; $S 'ip -br addr show wlan0; ip route | head -3; ping -c 2 -W 3 1.1.1.1 | tail -1'
