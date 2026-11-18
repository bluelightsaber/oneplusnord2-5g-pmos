# /etc/profile.d/99-denniz-welcome.sh: SSH login banner for the denniz headless server (live status + how it works).
# Only for interactive SSH logins; silence it per user with ~/.hushlogin.
case $- in *i*) ;; *) return 0 2>/dev/null || exit 0;; esac
[ -n "${SSH_CONNECTION:-}" ] && [ ! -e "$HOME/.hushlogin" ] && [ -z "${DENNIZ_WELCOME:-}" ] || return 0 2>/dev/null
export DENNIZ_WELCOME=1   # profile.d may be sourced twice (profile + bashrc)
_w() {
  b=""; for p in /sys/class/power_supply/*; do [ -r $p/capacity ] && [ "$(cat $p/type 2>/dev/null)" = Battery ] && b="$(cat $p/capacity)% $(cat $p/status 2>/dev/null)"; done
  t=""; for z in /sys/class/thermal/thermal_zone*; do v=$(cat $z/temp 2>/dev/null) && [ "${v:-0}" -gt ${t:-0} ] && t=$v; done
  ip4() { ip -4 -o addr show $1 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1; }
  eth=""; for i in $(ls /sys/class/net | grep -E '^(eth|enx|enp|usb[1-9])'); do a=$(ip4 $i); [ -n "$a" ] && eth="$eth $i=$a"; done
  dk=$(docker ps -q 2>/dev/null | wc -l); dka=$(docker ps -aq 2>/dev/null | wc -l)
  df1() { df -h "$1" 2>/dev/null | awk 'NR==2{print $3" / "$2" used ("$5")"}'; }
  cat <<EOT

  OnePlus Nord 2 5G (denniz, MT6893) - postmarketOS headless server
  ------------------------------------------------------------------
  kernel   $(uname -r)        up $(uptime | sed 's/.*up *//; s/, *[0-9]* user.*//')
  battery  ${b:-?}    max temp $(( ${t:-0} / 1000 ))C    load $(cut -d' ' -f1-3 /proc/loadavg)
  network  wlan0=$(ip4 wlan0)${eth}  tailscale=$(ip4 tailscale0)
  root /   $(df1 /)   (btrfs on 'super': system only)
  /data    $(df1 /data)   (btrfs on 'userdata': your data)
  docker   $dk running / $dka containers   (data-root /opt/docker)

  How it works
  - MAIN STORAGE: /data (224 GB btrfs on 'userdata') - put your files and compose projects there.
    / is the system only (10 GB on 'super', keep it lean).
  - DOCKER: data-root /opt/docker (images also in /var/lib/containerd), same btrfs as /data.
    Data mounts are 'nofail': the system boots without them (Docker then stays stopped).
  - UPDATES: 'sudo apk update && sudo apk upgrade' (postmarketOS/Alpine packages). The kernel is NOT
    updated by apk: it is our own image in the boot/recovery partitions (apk's kernel in /boot is unused).
  - Network: Wi-Fi first, Ethernet through a USB-C hub as fallback. Wi-Fi: 'nmtui', or
    'nmcli dev wifi list' / 'sudo nmcli dev wifi connect SSID --ask'.
  - USB-C role is automatic: hub/pendrive = host; PC = device (USB network, phone 172.16.42.1).
  - Screen: btop on the panel, blanks after 1 h idle; a short power press wakes it.
  - Power key: hold 4 s = reboot into recovery (rescue image); hold ~15 s = hardware reset.
  - 'sudo reboot' takes ~2 min (~90 s of black screen in the bootloader is normal).
    'sudo systemctl reboot --reboot-argument=recovery' = rescue image (fast).
    'poweroff' does NOT cut power on this phone: hold the power key instead.
  - Battery is held between 45 and 65 % (charge-limit.service) for 24/7 use on the charger.
  - Logs: 'journalctl -b' (persistent, also previous boots: 'journalctl --list-boots').

EOT
}
_w; unset -f _w ip4 df1 2>/dev/null
