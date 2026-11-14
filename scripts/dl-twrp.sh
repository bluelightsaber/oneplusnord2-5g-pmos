#!/bin/bash
# Download the official TWRP for denniz from TeamWin (EU mirror) and verify its published sha256.
set -eu
D=/srv/nord2-pmos/firmware-vendor/twrp
F=twrp-3.7.0_11-0-denniz.img
B=https://eu.dl.twrp.me/denniz
mkdir -p "$D"; cd "$D"
for x in "" .sha256 .md5 .asc; do
  curl -sSL --fail -e "$B/$F.html" -o "$F$x" "$B/$F$x"
done
ls -l
file "$F"
cat "$F.sha256"
sha256sum -c <(awk '{print $1"  '"$F"'"}' "$F.sha256") && echo SHA256-OK
md5sum -c <(awk '{print $1"  '"$F"'"}' "$F.md5") && echo MD5-OK
which gpg >/dev/null && echo "gpg present" || echo "no gpg"
