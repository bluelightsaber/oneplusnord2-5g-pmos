#!/bin/bash
# Re-dump large partitions from TWRP in 256 MiB chunks (adb exec-out stalls/truncates on long streams).
# Each chunk: timeout + sha256 compared with the phone, up to 6 tries. Then the whole image is checked
# against the phone's sha256 of the full device. Usage: dump-chunked.sh OUTDIR name:/dev/block/X [...]
set -u
N=/srv/nord2-pmos; SER=${SERIAL:?set SERIAL to the phone serial}
ADB="$N/platform-tools/adb -s $SER"
OUT=$1; shift; cd "$OUT" || exit 1
log() { echo "[$(date +%T)] $*"; }
BS=4194304; CNT=64; CH=$((BS*CNT))
for spec in "$@"; do
  n=${spec%%:*}; dev=${spec#*:}
  sz=$($ADB shell "blockdev --getsize64 $dev" </dev/null | tr -d '\r')
  nch=$(( (sz + CH - 1) / CH ))
  mkdir -p "chunks-$n"; log "$n $dev $sz B, $nch chunks"
  for i in $(seq 0 $((nch-1))); do
    c="chunks-$n/$(printf %04d $i)"; ok=0
    for t in 1 2 3 4 5 6; do
      want=$($ADB shell "dd if=$dev bs=$BS skip=$((i*CNT)) count=$CNT 2>/dev/null | sha256sum" </dev/null | cut -d' ' -f1 | tr -d '\r')
      timeout 120 $ADB exec-out "dd if=$dev bs=$BS skip=$((i*CNT)) count=$CNT 2>/dev/null" </dev/null > "$c"
      got=$(sha256sum "$c" | cut -d' ' -f1)
      [ -n "$want" ] && [ "$got" = "$want" ] && { ok=1; break; }
      log "  chunk $i try $t mismatch ($(stat -c %s "$c") B)"; sleep 3
    done
    [ $ok = 1 ] || { log "CHUNK-FAILED $n $i"; exit 1; }
  done
  cat chunks-$n/* > "$n.img"
  ls=$(sha256sum "$n.img" | cut -d' ' -f1)
  rs=$($ADB shell "sha256sum $dev" </dev/null | cut -d' ' -f1 | tr -d '\r')
  if [ "$ls" = "$rs" ] && [ "$(stat -c %s "$n.img")" = "$sz" ]; then
    grep -v "  $n.img\$" SHA256SUMS > SHA256SUMS.tmp 2>/dev/null; echo "$ls  $n.img" >> SHA256SUMS.tmp; mv SHA256SUMS.tmp SHA256SUMS
    rm -rf "chunks-$n"; log "OK   $n (chunked, $sz B)"
  else log "FAIL $n whole-image hash local=$ls phone=$rs"; fi
done
chmod -R go-rwx "$OUT"
log "CHUNKED-DONE"
