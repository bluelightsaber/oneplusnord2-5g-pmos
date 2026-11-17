#!/bin/bash
# Build a postmarketOS rootfs (generic qemu-aarch64 userland, console UI, systemd = pmOS default) with pmbootstrap
# and pack it as a tarball for RAM boots (pmos-ram.sh): $N/images/pmos-root.tgz. The kernel stays ours (built in).
# `install --no-image` skips pmbootstrap's SSH-key copy, so the denniz overlay is added here:
#   - ~user/.ssh/authorized_keys from ~/.ssh/id_ed25519_nord2.pub (dedicated key, created if missing)
#   - Docker + Tailscale enabled (52_tailscale.nft firewall rule; user in group docker)
#   - NetworkManager leaves usb0 alone (the initramfs already configured 172.16.42.1 on it) and the extra
#     interfaces of the MTK Wi-Fi driver (wlan1, ap0, p2p0): only wlan0 is scanned/used
# Password: ~/oneplusnord2-password.txt (never printed). Usage: pmos-rootfs.sh [--pack-only]
set -euo pipefail
renice -n 19 -p $$ >/dev/null; ionice -c3 -p $$
N=/srv/nord2-pmos; CFG=$N/pmbootstrap_v3.cfg; PMB="python3 $N/pmbootstrap/pmbootstrap.py -c $CFG"
grep -q "^aports = $N/" $CFG || { echo "refusing: aports in $CFG is not ours"; exit 1; }
K=~/.ssh/id_ed25519_nord2; [ -f $K ] || ssh-keygen -q -t ed25519 -N "" -C nord2-pmos -f $K
if [ "${1:-}" != --pack-only ]; then
  # extra packages for the denniz tools: i2c-tools (charge-limit, mp2650-dump), bluez, devmem2 (WFDMA dumps), btop;
  # server stack (as on the 9 Pro): Docker (+ compose, buildx, pmOS nftables rules for it) and Tailscale
  $PMB install --no-image --add i2c-tools,bluez,devmem2,btop,tcpdump,iw,docker,docker-cli-compose,docker-cli-buildx,postmarketos-config-nftables-docker,tailscale --password "$(cat ~/oneplusnord2-password.txt)" 2>&1 | grep -v "^\s*$" | tail -15
fi
R=$N/pmbootstrap-work/chroot_rootfs_qemu-aarch64
[ -e $R/sbin/init ] || { echo "no rootfs at $R"; exit 1; }
U=$(stat -c %u $R/home/user)
sudo -n install -d -m 700 -o $U -g $U $R/home/user/.ssh
sudo -n install -m 600 -o $U -g $U $K.pub $R/home/user/.ssh/authorized_keys
printf '[keyfile]\nunmanaged-devices=interface-name:usb0;interface-name:wlan1;interface-name:ap0;interface-name:p2p0\n' | sudo -n tee $R/etc/NetworkManager/conf.d/90-denniz-usb0.conf >/dev/null
# MTK gen4m firmware keeps transmitting with its own (NVRAM) MAC: a NM-randomized MAC makes 802.11 auth time out.
printf '[device]\nwifi.scan-rand-mac-address=no\n\n[connection]\nwifi.cloned-mac-address=permanent\nwifi.powersave=2\n' | \
  sudo -n tee $R/etc/NetworkManager/conf.d/91-denniz-mac.conf >/dev/null
# Server stack: Tailscale firewall rule, docker + tailscaled enabled, user in group docker (login: tailscale up)
sudo -n install -m 644 $N/repo/config/52_tailscale.nft $R/etc/nftables.d/52_tailscale.nft
for u in docker tailscaled; do
  [ -f $R/usr/lib/systemd/system/$u.service ] || { echo "missing $u.service in rootfs"; exit 1; }
  sudo -n ln -sfn /usr/lib/systemd/system/$u.service $R/etc/systemd/system/multi-user.target.wants/$u.service
done
grep -qE '^docker:[^:]*:[0-9]+:(.*,)?user(,|$)' $R/etc/group || \
  sudo -n sed -i -E '/^docker:/{s/:$/:user/;t;s/$/,user/}' $R/etc/group
grep -E '^docker:' $R/etc/group
sudo -n tar -C $R --numeric-owner --exclude=./proc/* --exclude=./sys/* --exclude=./dev/* --exclude=./boot/* \
  --exclude=./lib/modules/* --exclude=./usr/lib/modules/* -czf $N/images/pmos-root.tgz .
sudo -n chown pmos: $N/images/pmos-root.tgz; ls -la $N/images/pmos-root.tgz
