#!/bin/sh
# charge-limit.sh: keep the denniz battery between LOW and HIGH % (default 45..65) by toggling ONLY the MP2650
# charge-enable bit (0x5c reg 0x08 bit 4, read-modify-write via i2cset -m). The charger watchdog is off on denniz,
# so the bit stays as written. Fail-safe: on stop/error charging is re-enabled (never leave the phone unable to
# charge). Also stops charging above MAXTEMP (tenths of °C, gauge reading). Runs as charge-limit.service.
LOW=${LOW:-45}; HIGH=${HIGH:-65}; MAXTEMP=${MAXTEMP:-450}; PERIOD=${PERIOD:-60}
P=/sys/class/power_supply/bq28z610-0
B=$(for d in /sys/bus/i2c/devices/i2c-*; do readlink -f $d/device 2>/dev/null | grep -q 1101a000 && basename $d; done | sed "s/i2c-//" | head -1)
log() { echo "charge-limit: $*"; }
[ -n "$B" ] && [ -d $P ] || { log "no charger bus or gauge"; exit 1; }
chg() { i2cset -y -m 0x10 $B 0x5c 0x08 $1 b; }          # $1 = 0x10 enable, 0x00 disable
en() { echo $(( ($(i2cget -y $B 0x5c 0x08 b) >> 4) & 1 )); }
trap 'chg 0x10; log "stopped: charging re-enabled"; exit 0' TERM INT EXIT
log "start: keep $LOW..$HIGH %, max temp $MAXTEMP, bus i2c-$B, CHG_EN=$(en)"
while :; do
  c=$(cat $P/capacity); t=$(cat $P/temp); e=$(en)
  if [ "$t" -ge "$MAXTEMP" ]; then w=0; why="temp $t"
  elif [ "$c" -ge "$HIGH" ]; then w=0; why="cap $c% >= $HIGH"
  elif [ "$c" -le "$LOW" ]; then w=1; why="cap $c% <= $LOW"
  else w=$e; why=""; fi
  if [ "$w" != "$e" ]; then
    if [ "$w" = 1 ]; then chg 0x10; else chg 0x00; fi
    log "CHG_EN $e -> $w ($why), $(cat $P/voltage_now) uV, $(cat $P/current_now) uA"
  fi
  sleep $PERIOD
done
