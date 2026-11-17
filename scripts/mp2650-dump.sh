#!/bin/sh
# mp2650-dump.sh: READ-ONLY dump of the denniz MP2650 2S charger (0x5c on i2c11 = 1101a000, FIFO-mode i2c).
# Register meanings: docs/mp2650.md (from the oplus GPL driver). Needs i2c-tools; root.
set -e
A=0x5c
B=$(for d in /sys/bus/i2c/devices/i2c-*; do case "$(readlink -f $d/device 2>/dev/null)" in *1101a000*) basename $d;; esac; done | sed 's/i2c-//' | head -1)
[ -n "$B" ] || { echo "i2c11 (1101a000) not registered"; exit 1; }
echo "bus i2c-$B addr $A"
r() { i2cget -y $B $A $1 b; }
w() { i2cget -y $B $A $1 w; }
printf 'regs 00..15:'; for i in $(seq 0 21); do printf ' %s' $(r $i | sed 's/0x//'); done; echo
v() { echo $(( ( $(w $1) >> 6 ) * $2 / $3 )); }   # (raw>>6)*num/den
r08=$(r 0x08); r09=$(r 0x09); r13=$(r 0x13); r14=$(r 0x14)
echo "REG08=$r08 CHG_EN=$(( (r08>>4)&1 )) OTG_EN=$(( (r08>>5)&1 )) LEARN_EN(suspend)=$(( (r08>>3)&1 )) BFET_EN=$(( (r08>>1)&1 ))"
echo "REG09=$r09 WDT=$(( (r09>>4)&3 )) (0=off 1=40s 2=80s 3=160s) TERM_EN=$(( (r09>>6)&1 )) CHG_TIMER_EN=$(( (r09>>3)&1 ))"
echo "REG13=$r13 status=$(( (r13>>2)&3 )) (0=not 1=pre 2=fast 3=done) VIN_PG=$(( (r13>>1)&1 ))"
echo "REG14=$r14 (faults: ntc=$(( r14&7 )) bat_ovp=$(( (r14>>3)&1 )) chg=$(( (r14>>4)&3 )) wdt=$(( (r14>>7)&1 )))"
echo "IINLIM=$(( ($(r 0x00)&0x7f)*50 )) mA  ICHG=$(( $(r 0x02)*50 )) mA  VREG=$(( (($(r 0x04)>>1)&0x3f)*125/10 + 3712 )) mV per cell"
echo "VBAT=$(v 0x16 125 10) mV VSYS=$(v 0x18 125 10) mV IBAT=$(v 0x1a 125 10) mA VBUS=$(v 0x1c 25 1) mV IBUS=$(v 0x1e 625 100) mA"
