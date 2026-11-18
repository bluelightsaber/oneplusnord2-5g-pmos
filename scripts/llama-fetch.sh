#!/bin/bash
# llama-fetch.sh (run on buildhost): copy the pinned llama.cpp source (src/llama-dl, sha256 recorded at download),
# the saved G77 Mesa build and the test model to the phone's /var/tmp/llm, plus llama-build.sh.
# Env: PHONE (default user@172.16.42.1), LV (default v1.0.0).
set -euo pipefail
N=/srv/nord2-pmos; LV=${LV:-v1.0.0}; H=${PHONE:-user@172.16.42.1}
K="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -i $HOME/.ssh/id_ed25519_nord2"
cd $N/src/llama-dl && sha256sum -c llama.cpp-$LV.tar.gz.sha256
MESA=${MESA:-mesa-g77-26.3.0-sg.tgz}   # G77 Mesa with compute subgroups (mesa-g77-patch.py part 3)
(cd $N/images/mesa && sha256sum -c $MESA.sha256)
ssh $K $H 'mkdir -p /var/tmp/llm'
tar -cf - -C $N/src/llama-dl llama.cpp-$LV.tar.gz -C $N/images/mesa --transform "s,^$MESA\$,mesa-g77.tgz," $MESA \
  -C $N/src/models qwen2.5-0.5b-instruct-q4_k_m.gguf -C $N/repo/scripts llama-build.sh llama-mali-patch.py | ssh $K $H 'tar -C /var/tmp/llm -xf -'
ssh $K $H 'ls -la /var/tmp/llm; df -m /var/tmp | tail -1'
