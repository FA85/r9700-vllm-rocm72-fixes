#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

CONTAINER_TOOL="${CONTAINER_TOOL:-podman}"
IMAGE="${IMAGE:-localhost/r9700-vllm:v0.29.0-rocm72-minimal-fixes}"
EXPECTED_ORIGINAL_HSA_SHA256="bec3c44c469d79c79c70bded96ac1c88d1c5c5e0e4b7abfa26096029075090f7"

command -v "$CONTAINER_TOOL" >/dev/null 2>&1 || {
  echo "$CONTAINER_TOOL not found" >&2
  exit 1
}
"$CONTAINER_TOOL" image inspect "$IMAGE" >/dev/null

label() {
  "$CONTAINER_TOOL" image inspect --format \
    "{{index .Config.Labels \"$1\"}}" "$IMAGE"
}

[[ "$(label io.github.fa85.r9700-vllm.aiter-lds)" == \
  "aiter-0.1.19-gfx1201-minimal-backport" ]]
[[ "$(label io.github.fa85.r9700-vllm.rocr-async-events-backoff)" == \
  "ROCm/rocm-systems#7898-backport" ]]
[[ "$(label io.github.fa85.r9700-vllm.rocr-null-event-backoff)" == \
  "20-200us" ]]
[[ "$(label io.github.fa85.r9700-vllm.fix-set)" == \
  "aiter-lds,rocr-async-events-backoff,rocr-null-event-backoff" ]]

for unwanted in \
  io.local.r9700-tuning.hsa-hybrid-active-wait \
  io.local.r9700-tuning.hsa-true-blocking-wait \
  io.local.r9700-tuning.hip-device-schedule \
  io.local.r9700-tuning.hsa-symbol-map; do
  [[ -z "$(label "$unwanted")" ]] || {
    echo "Unexpected experimental label: $unwanted" >&2
    exit 1
  }
done

"$CONTAINER_TOOL" run --rm --pull=never --entrypoint /bin/sh "$IMAGE" -c '
  set -eu
  test ! -e /opt/r9700-debug
  test -z "${LD_PRELOAD:-}"
  AITER_FILE="$(python3 -c '\''import importlib.util; from pathlib import Path; print(Path(importlib.util.find_spec("aiter").origin).resolve().parent / "ops/triton/attention/unified_attention.py")'\'')"
  grep -q _r9700_unified_3d_lds_footprint "$AITER_FILE"
  test -f /opt/rocm-7.2.3/lib/libhsa-runtime64.so.1.18.0
'

patched_sha="$("$CONTAINER_TOOL" run --rm --pull=never --entrypoint sha256sum \
  "$IMAGE" /opt/rocm-7.2.3/lib/libhsa-runtime64.so.1.18.0 | awk '{print $1}')"
[[ "$patched_sha" != "$EXPECTED_ORIGINAL_HSA_SHA256" ]] || {
  echo "ROCr library was not replaced" >&2
  exit 1
}

echo "PASS: image contains exactly the three intended fixes"
echo "Patched ROCr SHA-256: $patched_sha"

if [[ "${GPU_TEST:-0}" == "1" ]]; then
  gpu_args=(--device /dev/kfd --device /dev/dri)
  if [[ "$CONTAINER_TOOL" == "podman" ]]; then
    gpu_args+=(--group-add keep-groups)
  fi
  "$CONTAINER_TOOL" run --rm --pull=never \
    "${gpu_args[@]}" \
    --entrypoint python3 "$IMAGE" -c '
import torch
count = torch.cuda.device_count()
print(f"HIP devices: {count}")
assert count > 0
for index in range(count):
    x = torch.ones(16, device=f"cuda:{index}")
    torch.cuda.synchronize(index)
    assert x.sum().item() == 16
'
  echo "PASS: HIP device smoke test"
fi
