#!/bin/sh
# llama-build.sh (run on the phone as root, after llama-fetch.sh): install build deps, unpack the G77 Mesa into
# /opt/mesa-g77 and build llama.cpp twice: CPU only (build-cpu) and with the OpenCL backend (build-cl).
# Run detached, memory-capped (an OOM hang ends in a watchdog reboot):
#   systemd-run --unit=llama-build -p MemoryMax=4G sh /var/tmp/llm/llama-build.sh (journalctl -u llama-build).
# Log: /var/tmp/llm/build.log. LV = llama.cpp version (default v1.0.0).
set -eu
exec >> /var/tmp/llm/build.log 2>&1
LV=${LV:-v1.0.0}; D=/var/tmp/llm; cd $D
apk add -q build-base cmake samurai linux-headers opencl-headers opencl-icd-loader-dev python3
[ -d /opt/mesa-g77 ] || tar -C / -xzf mesa-g77.tgz
[ -d llama.cpp ] || { tar -xzf llama.cpp-$LV.tar.gz && mv llama.cpp-${LV#v} llama.cpp; }
cd llama.cpp
[ -z "${PATCH:-}" ] || python3 $PATCH .   # e.g. PATCH=/var/tmp/llm/llama-mali-patch.py
J=${J:-3}   # each ggml-opencl.cpp job takes GBs: 8 jobs hung the RAM-only system (2026-11-17)
[ -n "${SKIP_CPU:-}" ] || {
cmake -S . -B build-cpu -G Ninja -DCMAKE_BUILD_TYPE=Release -DGGML_NATIVE=ON -DLLAMA_CURL=OFF -DLLAMA_BUILD_TESTS=OFF
cmake --build build-cpu -j$J --target llama-bench llama-cli llama-server
echo "CPU BUILD OK $(date)"
}
cmake -S . -B build-cl -G Ninja -DCMAKE_BUILD_TYPE=Release -DGGML_NATIVE=ON -DLLAMA_CURL=OFF -DLLAMA_BUILD_TESTS=ON \
  -DGGML_OPENCL=ON -DGGML_OPENCL_EMBED_KERNELS=ON -DGGML_OPENCL_USE_ADRENO_KERNELS=OFF
cmake --build build-cl -j$J --target llama-bench llama-cli test-backend-ops
echo "CL BUILD OK $(date)"
