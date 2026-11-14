#!/bin/bash
# Parallel (HTTP range) download of the official OnePlus Nord 2 EU rollback package from the Wayback Machine,
# then verification against the archive's content SHA-1 (base32). Each part retries until it has its exact size.
set -u
N=/srv/nord2-pmos
D=$N/firmware-vendor/oos11-rollback
F=$D/oplus_ota_downgrade_EU.zip
WANT=OIJN3XGTWJVDP4TAMC3K2VSJPYFQRCHV
URL="https://web.archive.org/web/20230207132242id_/https://oxygenos.oneplus.net/oplus_ota_downgrade_EU.zip"
SIZE=3785455123
PARTS=8
mkdir -p "$D/parts"
CH=$(( (SIZE + PARTS - 1) / PARTS ))
part() {
  local i=$1 s=$(( $1 * CH )) e=$(( ($1 + 1) * CH - 1 ))
  [ $e -ge $SIZE ] && e=$((SIZE - 1))
  local want=$(( e - s + 1 )) p="$D/parts/p$i" have
  for try in $(seq 1 50); do
    have=$(stat -c %s "$p" 2>/dev/null || echo 0)
    [ "$have" -eq "$want" ] && { echo "part $i done"; return 0; }
    [ "$have" -gt "$want" ] && { rm -f "$p"; have=0; }
    curl -s -L --fail -r $(( s + have ))-$e "$URL" >> "$p" || sleep 15
  done
  echo "part $i FAILED"; return 1
}
for i in $(seq 0 $((PARTS-1))); do part $i & done
wait
for i in $(seq 0 $((PARTS-1))); do cat "$D/parts/p$i"; done > "$F"
ls -l "$F"
[ "$(stat -c %s "$F")" -eq $SIZE ] || { echo "SIZE-MISMATCH"; exit 1; }
GOT=$(python3 -I -c 'import base64,hashlib,sys
h=hashlib.sha1()
with open(sys.argv[1],"rb") as f:
    for b in iter(lambda: f.read(1<<20), b""): h.update(b)
print(base64.b32encode(h.digest()).decode())' "$F")
echo "sha1-b32 got=$GOT want=$WANT"
if [ "$GOT" = "$WANT" ]; then echo VERIFY-OK; rm -rf "$D/parts"; else echo VERIFY-MISMATCH; fi
sha256sum "$F"
