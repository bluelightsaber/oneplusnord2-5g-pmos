# /etc/profile.d/99-denniz-welcome.sh (Spanish version): SSH login banner for the denniz headless server (live status + how it works).
# Only for interactive SSH logins; silence it per user with ~/.hushlogin.
case $- in *i*) ;; *) return 0 2>/dev/null || exit 0;; esac
[ -n "${SSH_CONNECTION:-}" ] && [ ! -e "$HOME/.hushlogin" ] && [ -z "${DENNIZ_WELCOME:-}" ] || return 0 2>/dev/null
export DENNIZ_WELCOME=1   # profile.d may be sourced twice (profile + bashrc)
_w() {
  b=""; for p in /sys/class/power_supply/*; do [ -r $p/capacity ] && [ "$(cat $p/type 2>/dev/null)" = Battery ] && b="$(cat $p/capacity)% $(sed "s/^Not charging/sin cargar/;s/^Charging/cargando/;s/^Discharging/descargando/;s/^Full/llena/" $p/status 2>/dev/null)"; done
  t=""; for z in /sys/class/thermal/thermal_zone*; do v=$(cat $z/temp 2>/dev/null) && [ "${v:-0}" -gt ${t:-0} ] && t=$v; done
  ip4() { ip -4 -o addr show $1 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1; }
  eth=""; for i in $(ls /sys/class/net | grep -E '^(eth|enx|enp|usb[1-9])'); do a=$(ip4 $i); [ -n "$a" ] && eth="$eth $i=$a"; done
  dk=$(docker ps -q 2>/dev/null | wc -l); dka=$(docker ps -aq 2>/dev/null | wc -l)
  df1() { df -h "$1" 2>/dev/null | awk 'NR==2{print $3" / "$2" usados ("$5")"}'; }
  cat <<EOT
  OnePlus Nord 2 5G (denniz, MT6893) - servidor postmarketOS sin pantalla
  -----------------------------------------------------------------------
  kernel   $(uname -r)        encendido $(uptime | sed 's/.*up *//; s/, *[0-9]* user.*//')
  batería  ${b:-?}    temp. máx. $(( ${t:-0} / 1000 ))C    carga $(cut -d' ' -f1-3 /proc/loadavg)
  red      wlan0=$(ip4 wlan0)${eth}  tailscale=$(ip4 tailscale0)
  /        $(df1 /)   (btrfs en 'super': solo el sistema)
  /data    $(df1 /data)   (btrfs en 'userdata': tus datos)
  docker   $dk en marcha / $dka contenedores   (data-root /opt/docker)

  Cómo funciona
  - ALMACENAMIENTO PRINCIPAL: /data (224 GB, btrfs en 'userdata'). Pon ahí tus archivos y proyectos compose.
    / es solo el sistema (10 GB en 'super'): mantenlo ligero.
  - DOCKER: carpeta de datos /opt/docker (las imágenes también en /var/lib/containerd), mismo btrfs que /data.
    Estos montajes son 'nofail': el sistema arranca sin ellos (y Docker se queda parado).
  - ACTUALIZAR: 'sudo apk update && sudo apk upgrade' (paquetes postmarketOS/Alpine). apk NO actualiza el
    kernel: es nuestra imagen propia en las particiones boot/recovery (el kernel de apk en /boot no se usa).
  - Red: primero Wi-Fi; Ethernet por un hub USB-C como respaldo. Wi-Fi: 'nmtui', o
    'nmcli dev wifi list' / 'sudo nmcli dev wifi connect SSID --ask'.
  - USB-C automático: hub/pendrive = host; PC = dispositivo (red USB, teléfono en 172.16.42.1).
  - Pantalla: btop en el panel; se apaga tras 1 h sin uso; una pulsación corta de Power la enciende.
  - Botón Power: mantener 4 s = reinicio a recovery (imagen de rescate); ~15 s = reset por hardware.
  - 'sudo reboot' tarda ~2 min (es normal ~90 s de pantalla negra en el bootloader).
    'sudo systemctl reboot --reboot-argument=recovery' = imagen de rescate (rápido).
    'poweroff' NO corta la corriente en este teléfono: mantén pulsado Power.
  - La batería se mantiene entre el 45 y el 65 % (charge-limit.service) para uso 24/7 en el cargador.
  - Logs: 'journalctl -b' (persistentes; arranques anteriores: 'journalctl --list-boots').

EOT
}
_w; unset -f _w ip4 df1 2>/dev/null
