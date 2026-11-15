#!/bin/bash
# Boot the full postmarketOS rootfs on denniz WITHOUT flashing anything but the recovery slot:
# recovery-slot image (our kernel + initramfs-usb) -> host IP on the ECM link -> rootfs tarball over HTTP into a
# tmpfs -> switch_root to systemd. Then: ssh -i ~/.ssh/id_ed25519_nord2 user@172.16.42.1
# Usage: [NOFLASH=1] pmos-ram.sh [IMG=images/test-denniz-usb5.img]   (needs images/pmos-root.tgz, pmos-rootfs.sh)
#   NOFLASH=1: the initramfs is already up (e.g. recovery entered by hand) -> skip slot-test.
set -eu
N=/srv/nord2-pmos; IMG=${1:-$N/images/test-denniz-usb5.img}; TGZ=$N/images/pmos-root.tgz
K=~/.ssh/id_ed25519_nord2; A=$N/repo/scripts/acm-run.sh
[ -f $TGZ ] || { echo "no $TGZ"; exit 1; }
[ -n "${NOFLASH:-}" ] || FLASH_RECOVERY=1 $N/repo/scripts/slot-test.sh $IMG 120 | tail -2
O=$N/tests/ram/$(date +%Y%m%d-%H%M%S); mkdir -p $O
acm() { echo "$1" | timeout 60 $A $O cmd; }
acm "touch /tmp/keep; uname -r" | tee $O/uname.txt
IF=""; for i in $(seq 15); do for n in /sys/class/net/*; do
  [ "$(cat $n/address 2>/dev/null)" = 02:00:00:d2:10:02 ] && IF=$(basename $n); done; [ -n "$IF" ] && break; sleep 1; done
[ -n "$IF" ] || { echo "no ECM interface on the host"; exit 1; }
sudo -n ip addr replace 172.16.42.2/24 dev $IF; sudo -n ip link set $IF up; echo "host $IF 172.16.42.2"
ping -c 2 -W 2 172.16.42.1 >/dev/null && echo "phone answers on 172.16.42.1" || echo "WARNING: no ping"
(cd $N/images && exec timeout 1200 python3 -m http.server 8000 --bind 172.16.42.2 >$O/http.log 2>&1) &
sleep 2
acm "mkdir -p /newroot && mount -t tmpfs -o size=6g,mode=755 tmpfs /newroot && ( cd /newroot && wget -q -O - http://172.16.42.2:8000/pmos-root.tgz | tar xz && [ -e /newroot/sbin/init ] && echo OK > /tmp/fetch.done || echo FAIL > /tmp/fetch.done ) > /tmp/fetch.log 2>&1 & echo started"
T0=$(date +%s); R=""
while [ $(( $(date +%s) - T0 )) -lt 900 ]; do
  sleep 10; R=$(acm "cat /tmp/fetch.done 2>/dev/null; df -m /newroot | tail -1" | tr '\n' ' '); echo "$(( $(date +%s) - T0 ))s: $R"
  echo "$R" | grep -qwE "OK|FAIL" && break   # the tty echoes the command, so match a whole word
done
echo "$R" | grep -qw OK || { acm "cat /tmp/fetch.log"; echo "fetch failed"; exit 1; }
acm "echo /sbin/init > /tmp/switchroot; echo SWITCHING"
echo "waiting for sshd ..."
for i in $(seq 60); do
  if timeout 3 bash -c "</dev/tcp/172.16.42.1/22" 2>/dev/null; then
    echo "SSH UP"; ssh -i $K -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 \
      user@172.16.42.1 'uname -a; cat /etc/os-release | head -2; uptime; systemctl is-system-running; systemctl --failed --no-legend' 2>&1 | tee $O/ssh-first.txt
    exit 0
  fi; sleep 3
done
echo "no sshd after 3 min"; exit 2
