#!/bin/sh
# mesa-g77-build.sh: build Alpine's Mesa (same version/sources as the distro package, sha512-checked against its
# APKBUILD) on the phone with the denniz patches (mesa-g77-patch.py: Mali-G77 model entry,
# v9 JM compute task split). Builds panfrost (GL/GLES/EGL/GBM), panvk (Vulkan) and rusticl (OpenCL) into /opt/mesa-g77.
# Patches: mesa-g77-patch.py (copy it to /var/tmp/mesa). Incremental: an existing build/ dir is reused.
# Expects the unpacked tree from the fetch step in /var/tmp/mesa/mesa-$V. Run as root; log: /var/tmp/mesa/build.log
set -eu
V=${V:-26.3.0}; S=/var/tmp/mesa/mesa-$V; P=/opt/mesa-g77
apk add -q build-base meson samurai pkgconf python3 py3-mako py3-yaml py3-packaging py3-ply py3-cparser bison flex \
  llvm23-dev clang23-dev libclc-dev rust cargo rust-bindgen spirv-llvm-translator-dev spirv-tools-dev glslang \
  glslang-dev libdrm-dev expat-dev zlib-dev zstd-dev elfutils-dev eudev-dev vulkan-loader-dev libxml2-dev cbindgen
cd $S
python3 /var/tmp/mesa/mesa-g77-patch.py $S
[ -d build ] || meson setup build --prefix=$P --buildtype=release -Db_ndebug=true \
  -Dgallium-drivers=panfrost -Dvulkan-drivers=panfrost -Dplatforms= -Dglx=disabled -Degl=enabled -Dgbm=enabled \
  -Dopengl=true -Dgles1=disabled -Dgles2=enabled -Dllvm=enabled -Dshared-llvm=enabled \
  -Dgallium-rusticl=true -Dgallium-rusticl-enable-drivers=panfrost -Drust_std=2021 \
  -Dgallium-va=disabled -Dvideo-codecs= -Dzstd=enabled -Dexpat=enabled -Dxmlconfig=enabled -Dshader-cache=enabled \
  -Dbuild-tests=false -Dvalgrind=disabled -Dlibunwind=disabled
ninja -C build
ninja -C build install
tar -C / -czf /var/tmp/mesa/mesa-g77-$V.tgz ${P#/}
echo "MESA BUILD OK $(date)"
