#!/bin/bash
# mesa-g77-fetch.sh (run on buildhost): download Alpine's Mesa sources once into $N/src/mesa-dl (cached), verify them
# against Alpine's APKBUILD sha512sums, copy them + mesa-g77-patch.py to the phone and unpack the tree in
# /var/tmp/mesa/mesa-$V with the Rust crates set up like the APKBUILD's prepare(). Then run mesa-g77-build.sh there.
# Env: PHONE (default user@172.16.42.1), V (default 26.3.0).
set -euo pipefail
N=/srv/nord2-pmos; V=${V:-26.3.0}; D=$N/src/mesa-dl; mkdir -p $D; cd $D
H=${PHONE:-user@172.16.42.1}
K="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -i $HOME/.ssh/id_ed25519_nord2"
CRATES="paste:1.0.14 proc-macro2:1.0.86 quote:1.0.33 syn:2.0.68 unicode-ident:1.0.12 rustc-hash:2.1.1"
fetch() { [ -s "$2" ] && return 0; wget -q -O "$2.part" "$1"; mv -f "$2.part" "$2"; }
fetch https://gitlab.alpinelinux.org/alpine/aports/-/raw/master/main/mesa/APKBUILD APKBUILD
grep -q "^pkgver=$V$" APKBUILD || { echo "APKBUILD is not mesa $V"; exit 1; }
fetch https://mesa.freedesktop.org/archive/mesa-$V.tar.xz mesa-$V.tar.xz
for c in $CRATES; do n=${c%%:*}; v=${c##*:}; fetch https://static.crates.io/crates/$n/$n-$v.crate $n-$v.tar.gz; done
sed -n '/^sha512sums="/,/^"/p' APKBUILD | grep -E "\.tar\.(xz|gz)$" > sums
sha512sum -c --quiet sums && echo "sources verified"
ssh $K $H 'mkdir -p /var/tmp/mesa'
tar -cf - mesa-$V.tar.xz *.tar.gz -C $N/repo/scripts mesa-g77-patch.py mesa-g77-build.sh | ssh $K $H 'tar -C /var/tmp/mesa -xf -'
ssh $K $H "set -e; cd /var/tmp/mesa; rm -rf mesa-$V; tar -xf mesa-$V.tar.xz; cd mesa-$V/subprojects
  for p in paste-1.0.14:paste-1-rs proc-macro2-1.0.86:proc-macro2-1-rs quote-1.0.33:quote-1-rs syn-2.0.68:syn-2-rs \
           unicode-ident-1.0.12:unicode-ident-1-rs rustc-hash-2.1.1:rustc-hash-2-rs; do
    rm -f \${p##*:}.wrap; tar -xzf ../../\${p%%:*}.tar.gz; mv \${p%%:*} \${p##*:}
    cp packagefiles/\${p##*:}/meson.build \${p##*:}/; done
  echo unpacked: \$(ls -d /var/tmp/mesa/mesa-$V)"
