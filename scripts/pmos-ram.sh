#!/bin/bash
# Boot the full postmarketOS rootfs on denniz WITHOUT flashing anything but the recovery slot:
# recovery-slot image (our kernel + initramfs-usb) -> host IP on the ECM link -> rootfs tarball over HTTP into a
# tmpfs -> switch_root to systemd. Then: ssh -i ~/.ssh/id_ed25519_nord2 user@172.16.42.1
# Usage: [NOFLASH=1] [FW=…/wifi-fw.tgz] pmos-ram.sh [IMG=images/test-denniz-usb5.img]   (needs images/pmos-root.tgz)
#   FW (default firmware-vendor/oos11-A20/wifi-fw.tgz from wifi-fw.sh, private) is unpacked over the rootfs if present.
#   NOFLASH=1: the initramfs is already up (e.g. recovery entered by hand) -> skip slot-test.
set -eu
N=/srv/nord2-pmos; IMG=${1:-$N/images/test-denniz-usb5.img}; TGZ=$N/images/pmos-root.tgz
K=~/.ssh/id_ed25519_nord2; A=$N/repo/scripts/acm-run.sh; FW=${FW:-$N/firmware-vendor/oos11-A20/wifi-fw.tgz}
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
pkill -f 'http.server 8000 --bind 172.16.42.2' || true; sleep 1   # a leftover server would serve a deleted dir (404)
W=$(mktemp -d); ln -s $TGZ $W/root.tgz; [ -f $FW ] && ln -s $FW $W/fw.tgz
(cd $W && exec timeout 1200 python3 -m http.server 8000 --bind 172.16.42.2 >$O/http.log 2>&1) &
HS=$!; trap 'kill $HS 2>/dev/null; pkill -f "http.server 8000 --bind 172.16.42.2"; rm -rf $W' EXIT
sleep 2
acm "mkdir -p /newroot && mount -t tmpfs -o size=6g,mode=755 tmpfs /newroot && ( cd /newroot && wget -q -O - http://172.16.42.2:8000/root.tgz | tar xz && { wget -q -O - http://172.16.42.2:8000/fw.tgz | tar xz || true; } && [ -e /newroot/sbin/init ] && echo OK > /tmp/fetch.done || echo FAIL > /tmp/fetch.done ) > /tmp/fetch.log 2>&1 & echo started"
T0=$(date +%s); R=""
while [ $(( $(date +%s) - T0 )) -lt 900 ]; do
  sleep 10; R=$(acm "echo RES=\$(cat /tmp/fetch.done 2>/dev/null); df -m /newroot | tail -1" | tr '\n' ' '); echo "$(( $(date +%s) - T0 ))s: $R"
  echo "$R" | grep -qE "RES=(OK|FAIL)" && break   # the tty echoes the command: match the expanded value only
done
echo "$R" | grep -q "RES=OK" || { acm "cat /tmp/fetch.log"; echo "fetch failed"; exit 1; }
acm "echo /sbin/init > /tmp/switchroot; echo SWITCHING"
echo "waiting for sshd ..."
for i in $(seq 60); do
  if timeout 3 bash -c "</dev/tcp/172.16.42.1/22" 2>/dev/null; then
    echo "SSH UP"
    # Everything is built in, but modprobe (zramstart, systemd-modules-load) needs /lib/modules/$(uname -r) to know.
    B=$N/src/build-denniz
    # Full kernel: ship all modules (build-kernel.sh -> modules.tgz, usr/lib/modules/<ver>); old builds without it
    # only get the modules.builtin* lists (modprobe of built-in features needs /lib/modules/$(uname -r) to exist).
    if [ -f $B/modules.tgz ]; then cat $B/modules.tgz
    else tar -C $B --transform 's,^,usr/lib/modules/KVER/,' -czf - modules.builtin modules.builtin.modinfo modules.order 2>/dev/null; fi | \
      ssh -i $K -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR user@172.16.42.1 'cat > /tmp/kmod.tgz'
    ssh -i $K -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR user@172.16.42.1 \
      "sudo -S -p '' sh -c 'cd / && tar -xzf /tmp/kmod.tgz && rm /tmp/kmod.tgz && { [ -d usr/lib/modules/KVER ] && mv usr/lib/modules/KVER usr/lib/modules/\$(uname -r) || true; } && depmod && echo modules: \$(find /lib/modules/\$(uname -r) -name \\*.ko\\* | wc -l) && systemctl restart postmarketos-zram-swap; swapon --show=NAME,SIZE --noheadings'" < ~/oneplusnord2-password.txt
    # Project config + helper scripts: NM Wi-Fi-first route metrics, usb-mode.sh, mp2650-dump.sh (/usr/local/sbin)
    S=$(mktemp -d); mkdir -p $S/etc/NetworkManager/conf.d $S/usr/local/sbin
    cp $N/repo/config/50-denniz-route-metric.conf $S/etc/NetworkManager/conf.d/
    for f in usb-mode mp2650-dump charge-limit; do install -m 755 $N/repo/scripts/$f.sh $S/usr/local/sbin/$f; done
    mkdir -p $S/etc/systemd/system/multi-user.target.wants   # charge-limit.service (45-65 %), enabled
    cp $N/repo/config/charge-limit.service $S/etc/systemd/system/
    ln -s ../charge-limit.service $S/etc/systemd/system/multi-user.target.wants/charge-limit.service
    cp $N/repo/config/machine-info $S/etc/machine-info   # bluez name (else "QEMU aarch64" from DMI)
    tar -C $S --owner=0 --group=0 -czf - etc usr | ssh -i $K -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o LogLevel=ERROR user@172.16.42.1 'cat > /tmp/extra.tgz'; rm -rf $S
    ssh -i $K -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR user@172.16.42.1 \
      "sudo -S -p '' sh -c 'tar -C / -xzf /tmp/extra.tgz && rm /tmp/extra.tgz && nmcli general reload conf; systemctl daemon-reload; command -v i2cset >/dev/null && systemctl start charge-limit; systemctl try-restart bluetooth; true'" < ~/oneplusnord2-password.txt && echo "extra config installed"
    WP=$N/firmware-vendor/private/home-wifi.nmconnection   # private Wi-Fi profile (wifi-connect.sh), if any
    if [ -f $WP ] && [ -z "${NOWIFI:-}" ]; then   # NOWIFI=1: leave it out (e.g. to capture the first attempt)
      ssh -i $K -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR user@172.16.42.1 \
        'umask 077; cat > /tmp/w.nmconnection' < $WP
      ssh -i $K -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR user@172.16.42.1 \
        "sudo -S -p '' sh -c 'install -m 600 /tmp/w.nmconnection /etc/NetworkManager/system-connections/home-wifi.nmconnection && rm /tmp/w.nmconnection && nmcli connection reload'" < ~/oneplusnord2-password.txt && echo "wifi profile installed"
    fi
    ssh -i $K -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 \
      user@172.16.42.1 'uname -a; cat /etc/os-release | head -2; uptime; systemctl is-system-running; systemctl --failed --no-legend' 2>&1 | tee $O/ssh-first.txt
    exit 0
  fi; sleep 3
done
echo "no sshd after 3 min"; exit 2
