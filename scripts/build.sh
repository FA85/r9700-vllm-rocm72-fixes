#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

case "${BASH_SOURCE[0]}" in
  */*) SCRIPT_DIR="${BASH_SOURCE[0]%/*}" ;;
  *) SCRIPT_DIR="." ;;
esac
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"

CONTAINER_TOOL="${CONTAINER_TOOL:-podman}"
IMAGE="${IMAGE:-localhost/r9700-vllm:v0.29.0-rocm72-minimal-fixes}"
BASE_IMAGE="${BASE_IMAGE:-docker.io/vllm/vllm-openai-rocm:v0.29.0@sha256:e5e47f6aaab675c252c381f0dac237b31b10d87bb74d092b07fb4065efd7f5a1}"

command -v "$CONTAINER_TOOL" >/dev/null 2>&1 || {
  echo "$CONTAINER_TOOL not found" >&2
  exit 1
}

if "$CONTAINER_TOOL" image inspect "$BASE_IMAGE" >/dev/null 2>&1; then
  echo "Using local base image: $BASE_IMAGE"
else
  "$CONTAINER_TOOL" pull "$BASE_IMAGE"
fi
"$CONTAINER_TOOL" build \
  --pull=false \
  --build-arg "BASE_IMAGE=$BASE_IMAGE" \
  --tag "$IMAGE" \
  --file "$ROOT_DIR/Containerfile" \
  "$ROOT_DIR"

IMAGE="$IMAGE" CONTAINER_TOOL="$CONTAINER_TOOL" \
  bash "$SCRIPT_DIR/verify.sh"

echo "Built and verified: $IMAGE"
