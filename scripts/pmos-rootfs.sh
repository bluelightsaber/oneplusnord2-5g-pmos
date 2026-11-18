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
# Safety nets (untested 2026-11-17): systemd feeds the hardware watchdog; a boot stuck before multi-user reboots
sudo -n install -D -m 644 $N/repo/config/10-denniz-watchdog.conf $R/etc/systemd/system.conf.d/10-denniz-watchdog.conf
sudo -n install -D -m 644 $N/repo/config/multi-user-timeout.conf $R/etc/systemd/system/multi-user.target.d/10-denniz-timeout.conf
# Server stack: Tailscale firewall rule, docker + tailscaled enabled, user in group docker (login: tailscale up)
sudo -n install -m 644 $N/repo/config/52_tailscale.nft $R/etc/nftables.d/52_tailscale.nft
for u in docker tailscaled; do
  [ -f $R/usr/lib/systemd/system/$u.service ] || { echo "missing $u.service in rootfs"; exit 1; }
  sudo -n ln -sfn /usr/lib/systemd/system/$u.service $R/etc/systemd/system/multi-user.target.wants/$u.service
done
grep -qE '^docker:[^:]*:[0-9]+:(.*,)?user(,|$)' $R/etc/group || \
  sudo -n sed -i -E '/^docker:/{s/:$/:user/;t;s/$/,user/}' $R/etc/group
grep -E '^docker:' $R/etc/group
# Wi-Fi TX-hang recovery (gateway ping, WMT power cycle)
sudo -n install -D -m 755 $N/repo/scripts/wifi-ensure.sh $R/usr/local/sbin/wifi-ensure
sudo -n install -m 644 $N/repo/config/wifi-ensure.service $R/etc/systemd/system/
sudo -n ln -sfn ../wifi-ensure.service $R/etc/systemd/system/multi-user.target.wants/wifi-ensure.service
# USB role: no Type-C detection, so switch to host when no PC configures the gadget (OTG hub: Ethernet, pendrive)
sudo -n install -D -m 755 $N/repo/scripts/usb-role-auto.sh $R/usr/local/sbin/usb-role-auto
sudo -n install -m 644 $N/repo/config/usb-role-auto.service $R/etc/systemd/system/
sudo -n ln -sfn ../usb-role-auto.service $R/etc/systemd/system/multi-user.target.wants/usb-role-auto.service
# Panel console (needs a kernel with simpledrm + denniz-lkfb; skipped by ConditionPathExists=/dev/fb0 otherwise):
# btop on tty1 in landscape, blank after 1 h idle, wake on power/volume keys; a short power press never powers off
S=$N/repo/config/screen
sudo -n install -D -m 644 $S/60-powerkey.conf $R/etc/systemd/logind.conf.d/60-powerkey.conf
sudo -n install -D -m 644 $S/20-denniz-console.conf $R/etc/sysctl.d/20-denniz-console.conf
sudo -n install -D -m 644 $S/denniz-console.tmpfiles $R/etc/tmpfiles.d/denniz-console.conf
sudo -n install -D -m 755 $S/screen-idle $R/usr/local/bin/screen-idle
sudo -n install -m 644 $S/btop-console.service $S/screen-idle.service $R/etc/systemd/system/
echo "TIMEOUT=3600" | sudo -n tee $R/etc/screen-idle.conf >/dev/null
for u in btop-console screen-idle; do sudo -n ln -sfn ../$u.service $R/etc/systemd/system/multi-user.target.wants/$u.service; done
sudo -n rm -f $R/etc/systemd/system/getty.target.wants/getty@tty1.service
# reboot target for MediaTek LK (TOPRGU nonrst2) as a systemd-shutdown hook + hold power 4 s => reboot to recovery.
# Default target "recovery" while `boot` is not ours; set /etc/denniz-reboot-default to "normal" after flashing boot.
B=$N/repo/config/reboot
sudo -n install -D -m 755 $B/denniz-reboot-mode $R/usr/local/sbin/denniz-reboot-mode
sudo -n mkdir -p $R/usr/lib/systemd/system-shutdown
sudo -n ln -sfn /usr/local/sbin/denniz-reboot-mode $R/usr/lib/systemd/system-shutdown/denniz-reboot-mode
sudo -n install -D -m 755 $B/powerkey-rescue $R/usr/local/bin/powerkey-rescue
sudo -n install -m 644 $B/powerkey-rescue.service $R/etc/systemd/system/
sudo -n ln -sfn ../powerkey-rescue.service $R/etc/systemd/system/multi-user.target.wants/powerkey-rescue.service
echo "${REBOOT_DEFAULT:-recovery}" | sudo -n tee $R/etc/denniz-reboot-default >/dev/null
# SSH login banner (live status + how the server works)
sudo -n install -D -m 644 $N/repo/config/motd/99-denniz-welcome${WELCOME_LANG:+.$WELCOME_LANG}.sh $R/etc/profile.d/99-denniz-welcome.sh
sudo -n truncate -s 0 $R/etc/motd 2>/dev/null || true
sudo -n tar -C $R --numeric-owner --exclude=./proc/* --exclude=./sys/* --exclude=./dev/* --exclude=./boot/* \
  --exclude=./lib/modules/* --exclude=./usr/lib/modules/* -czf $N/images/pmos-root.tgz .
sudo -n chown pmos: $N/images/pmos-root.tgz; ls -la $N/images/pmos-root.tgz
