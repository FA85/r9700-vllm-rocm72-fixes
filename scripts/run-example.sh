#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

CONTAINER_TOOL="${CONTAINER_TOOL:-podman}"
IMAGE="${IMAGE:-localhost/r9700-vllm:v0.29.0-rocm72-minimal-fixes}"
MODEL="${MODEL:-Qwen/Qwen3.8-27B-FP8}"
CONTAINER_NAME="${CONTAINER_NAME:-vllm-r9700}"

extra_args=()
if [[ "$CONTAINER_TOOL" == "podman" ]]; then
  extra_args+=(--group-add keep-groups)
fi

exec "$CONTAINER_TOOL" run --rm \
  --name "$CONTAINER_NAME" \
  --network host --ipc host \
  --device /dev/kfd --device /dev/dri \
  "${extra_args[@]}" \
  -e HIP_VISIBLE_DEVICES="${HIP_VISIBLE_DEVICES:-0,1}" \
  -e NCCL_PROTO="${NCCL_PROTO:-Simple}" \
  -v "${HF_CACHE:-$HOME/.cache/huggingface}:/root/.cache/huggingface" \
  "$IMAGE" "$MODEL" \
  --tensor-parallel-size "${TENSOR_PARALLEL_SIZE:-2}" \
  "$@"
