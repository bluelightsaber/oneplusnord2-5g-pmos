#!/bin/bash
# Read-only BROM test for the Nord 2 with mtkclient (reused from /mnt/buildhost/epad, not modified).
# Reads the GPT, seccfg and lk through BROM + DA and compares them with the TWRP backup.
# Writes nothing to the phone. NO final "reset": on denniz the DA reset left the phone re-enumerating as
# 0e8d:0003 and the mtk process stuck in D state inside buildhost's xhci (xhci_setup_device) until the cable
# was pulled (2026-11-14). mtkclient disables the watchdog: when the script prints DONE, UNPLUG the cable,
# then hold Power + Vol Up ~15 s to reboot.
# Usage: brom-test.sh   (then: phone off, cable out, hold Vol+ and Vol-, plug cable into buildhost)
set -u
N=/srv/nord2-pmos
MTK=/opt/mtkclient-venv/bin/mtk
BK=$N/backups/partitions/oos11-A20-20261114-1932
OUT=$N/tests/brom-$(date +%Y%m%d-%H%M)
mkdir -p "$OUT" && cd "$OUT" || exit 1
rm -f .state
cat > cmds.txt <<'C'
printgpt
r seccfg seccfg.bin
r lk lk.bin
C
echo "OUT=$OUT"
timeout 1800 "$MTK" script cmds.txt > mtk.log 2>&1
echo "mtk exit=$?" >> mtk.log
for p in seccfg lk; do
  a=$(sha256sum $p.bin 2>/dev/null | cut -d" " -f1); b=$(sha256sum $BK/$p.img 2>/dev/null | cut -d" " -f1)
  echo "$p brom=${a:-none} twrp=${b:-none} $([ -n "$a" ] && [ "$a" = "$b" ] && echo MATCH || echo DIFF)" >> result.txt
done
grep -E "^[a-z0-9_]+: +Offset" mtk.log > gpt-brom.txt
echo "DONE - unplug the phone now, then Power+VolUp 15 s" >> result.txt
