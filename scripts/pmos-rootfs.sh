#!/bin/bash
# Build a postmarketOS rootfs (generic qemu-aarch64 userland, console UI, systemd = pmOS default) with pmbootstrap
# and pack it as a tarball for RAM boots (pmos-ram.sh): $N/images/pmos-root.tgz. The kernel stays ours (built in).
# `install --no-image` skips pmbootstrap's SSH-key copy, so the denniz overlay is added here:
#   - ~user/.ssh/authorized_keys from ~/.ssh/id_ed25519_nord2.pub (dedicated key, created if missing)
#   - NetworkManager leaves usb0 alone (the initramfs already configured 172.16.42.1 on it)
# Password: ~/oneplusnord2-password.txt (never printed). Usage: pmos-rootfs.sh [--pack-only]
set -euo pipefail
renice -n 19 -p $$ >/dev/null; ionice -c3 -p $$
N=/srv/nord2-pmos; CFG=$N/pmbootstrap_v3.cfg; PMB="python3 $N/pmbootstrap/pmbootstrap.py -c $CFG"
grep -q "^aports = $N/" $CFG || { echo "refusing: aports in $CFG is not ours"; exit 1; }
K=~/.ssh/id_ed25519_nord2; [ -f $K ] || ssh-keygen -q -t ed25519 -N "" -C nord2-pmos -f $K
if [ "${1:-}" != --pack-only ]; then
  $PMB install --no-image --password "$(cat ~/oneplusnord2-password.txt)" 2>&1 | grep -v "^\s*$" | tail -15
fi
R=$N/pmbootstrap-work/chroot_rootfs_qemu-aarch64
[ -e $R/sbin/init ] || { echo "no rootfs at $R"; exit 1; }
U=$(stat -c %u $R/home/user)
sudo -n install -d -m 700 -o $U -g $U $R/home/user/.ssh
sudo -n install -m 600 -o $U -g $U $K.pub $R/home/user/.ssh/authorized_keys
printf '[keyfile]\nunmanaged-devices=interface-name:usb0\n' | sudo -n tee $R/etc/NetworkManager/conf.d/90-denniz-usb0.conf >/dev/null
sudo -n tar -C $R --numeric-owner --exclude=./proc/* --exclude=./sys/* --exclude=./dev/* --exclude=./boot/* \
  --exclude=./lib/modules/* --exclude=./usr/lib/modules/* -czf $N/images/pmos-root.tgz .
sudo -n chown pmos: $N/images/pmos-root.tgz; ls -la $N/images/pmos-root.tgz
