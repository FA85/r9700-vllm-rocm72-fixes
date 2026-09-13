#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

case "${BASH_SOURCE[0]}" in
  */*) SCRIPT_DIR="${BASH_SOURCE[0]%/*}" ;;
  *) SCRIPT_DIR="." ;;
esac
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"

BUILD_USER="${BUILD_USER:-vllm}"
TUNING_SOURCE="${TUNING_SOURCE:-archive}"
TUNING_ARCHIVE="${TUNING_ARCHIVE:-$ROOT_DIR/tunings/r9700-vllm-v029-qwen38-fp8-tp2.tar.gz}"
TUNING_ARCHIVE_SHA256="${TUNING_ARCHIVE_SHA256:-7152bc3aad02e1b8f92f347038f06e9502af512d4d31bb3f2086b73f440d8f5c}"
TUNING_REPO="${TUNING_REPO:-https://github.com/FA85/r9700-vllm-tuning.git}"
TUNING_REF="${TUNING_REF:-codex/v0.29.0-tuning}"
TUNING_DIR="${TUNING_DIR:-}"
UPSTREAM_IMAGE="${UPSTREAM_IMAGE:-docker.io/vllm/vllm-openai-rocm@sha256:e5e47f6aaab675c252c381f0dac237b31b10d87bb74d092b07fb4065efd7f5a1}"
TUNED_IMAGE="${TUNED_IMAGE:-localhost/vllm-r9700:qwen38-v0.29.0-tuned}"
IMAGE="${IMAGE:-localhost/vllm-r9700:qwen38-v0.29.0-tuned-fixes}"
MODEL="${MODEL:-Qwen/Qwen3.8-27B-FP8}"

usage() {
  cat <<'EOF'
Usage:
  sudo bash scripts/build-with-tunings.sh

Useful environment overrides:
  GPU_TEST=1             Include the R9700 HIP smoke test.
  BUILD_USER=vllm        Account owning the rootless Podman image store.
  TUNING_SOURCE=archive  Use bundled archive (default) or git.
  TUNING_ARCHIVE=PATH    Override the bundled tuning archive.
  TUNING_ARCHIVE_SHA256  Expected SHA-256 for an overridden archive.
  TUNING_REPO=URL        Tuning Git repository (HTTPS or SSH).
  TUNING_REF=BRANCH      Tuning branch or tag.
  TUNING_DIR=PATH        Reuse a local tuning checkout instead of cloning.
  TUNED_IMAGE=IMAGE      Intermediate tuned image name.
  IMAGE=IMAGE            Final combined image name.
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  "") ;;
  *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
esac

# Root is convenient for a one-command invocation, but the images must land in
# the rootless Podman store used to run vLLM. Re-execute as that account.
if [[ "$EUID" -eq 0 ]]; then
  id "$BUILD_USER" >/dev/null 2>&1 || {
    echo "Build user does not exist: $BUILD_USER" >&2
    exit 1
  }
  build_uid="$(id -u "$BUILD_USER")"
  runtime_dir="/run/user/$build_uid"
  [[ -d "$runtime_dir" ]] || {
    echo "Missing $runtime_dir; start a login session for $BUILD_USER first." >&2
    exit 1
  }
  exec sudo -u "$BUILD_USER" -H env \
    XDG_RUNTIME_DIR="$runtime_dir" \
    BUILD_USER="$BUILD_USER" \
    TUNING_SOURCE="$TUNING_SOURCE" \
    TUNING_ARCHIVE="$TUNING_ARCHIVE" \
    TUNING_ARCHIVE_SHA256="$TUNING_ARCHIVE_SHA256" \
    TUNING_REPO="$TUNING_REPO" \
    TUNING_REF="$TUNING_REF" \
    TUNING_DIR="$TUNING_DIR" \
    UPSTREAM_IMAGE="$UPSTREAM_IMAGE" \
    TUNED_IMAGE="$TUNED_IMAGE" \
    IMAGE="$IMAGE" \
    MODEL="$MODEL" \
    GPU_TEST="${GPU_TEST:-0}" \
    bash "$ROOT_DIR/scripts/build-with-tunings.sh" "$@"
fi

for command_name in podman python3; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "$command_name not found" >&2
    exit 1
  }
done

temporary_root=""
cleanup() {
  if [[ -n "$temporary_root" && -d "$temporary_root" ]]; then
    rm -rf -- "$temporary_root"
  fi
}
trap cleanup EXIT

if [[ -n "$TUNING_DIR" ]]; then
  TUNING_DIR="$(cd -- "$TUNING_DIR" && pwd -P)"
  echo "Using local tuning checkout: $TUNING_DIR"
elif [[ "$TUNING_SOURCE" == "archive" ]]; then
  for command_name in tar sha256sum; do
    command -v "$command_name" >/dev/null 2>&1 || {
      echo "$command_name not found" >&2
      exit 1
    }
  done
  temporary_root="$(mktemp -d)"
  TUNING_DIR="$temporary_root/archive"
  mkdir -p "$TUNING_DIR"
  [[ -f "$TUNING_ARCHIVE" ]] || {
    echo "Tuning archive not found: $TUNING_ARCHIVE" >&2
    exit 1
  }
  echo "Using bundled tuning archive: $TUNING_ARCHIVE"
  actual_archive_sha256="$(sha256sum "$TUNING_ARCHIVE" | awk '{print $1}')"
  [[ "$actual_archive_sha256" == "$TUNING_ARCHIVE_SHA256" ]] || {
    echo "Tuning archive SHA-256 mismatch" >&2
    echo "Expected: $TUNING_ARCHIVE_SHA256" >&2
    echo "Actual:   $actual_archive_sha256" >&2
    exit 1
  }
  echo "PASS: tuning archive SHA-256"
  tar -xzf "$TUNING_ARCHIVE" -C "$TUNING_DIR"
  cat "$TUNING_DIR/tunings/SETUP_SCOPE.md"
elif [[ "$TUNING_SOURCE" == "git" ]]; then
  command -v git >/dev/null 2>&1 || {
    echo "git not found" >&2
    exit 1
  }
  temporary_root="$(mktemp -d)"
  TUNING_DIR="$temporary_root/r9700-vllm-tuning"
  echo "Fetching tuning set $TUNING_REF from $TUNING_REPO"
  GIT_TERMINAL_PROMPT=0 git clone --depth 1 --branch "$TUNING_REF" \
    "$TUNING_REPO" "$TUNING_DIR"
else
  echo "TUNING_SOURCE must be 'archive' or 'git': $TUNING_SOURCE" >&2
  exit 2
fi

tuning_root="$TUNING_DIR/r9700-tuning"
verify_tuning="$tuning_root/scripts/verify_published_configs.py"
build_tuning="$tuning_root/scripts/build_tuned_vllm_image.sh"

[[ -f "$verify_tuning" && -f "$build_tuning" ]] || {
  echo "The selected checkout is not the published v0.29.0 tuning tree." >&2
  exit 1
}

echo "Verifying published tuning files"
python3 "$verify_tuning"

echo "Pulling immutable upstream image"
podman pull "$UPSTREAM_IMAGE"

echo "Building tuning layer: $TUNED_IMAGE"
bash "$build_tuning" \
  --root "$tuning_root" \
  --image "$UPSTREAM_IMAGE" \
  --model "$MODEL" \
  --tp-size 2 \
  --tag "$TUNED_IMAGE"

echo "Building AITER/ROCr fixes: $IMAGE"
BASE_IMAGE="$TUNED_IMAGE" \
IMAGE="$IMAGE" \
CONTAINER_TOOL=podman \
  bash "$ROOT_DIR/scripts/build.sh"

if [[ "${GPU_TEST:-0}" == "1" ]]; then
  echo "The R9700 HIP smoke test was included in verification."
else
  echo "Static verification passed. Run again with GPU_TEST=1 on the R9700 host"
  echo "to include the HIP device smoke test."
fi

echo
echo "Combined image built successfully:"
echo "  $IMAGE"
echo
echo "Start and benchmark guidance:"
echo "  $ROOT_DIR/BUILD_WITH_TUNINGS.de.md"
