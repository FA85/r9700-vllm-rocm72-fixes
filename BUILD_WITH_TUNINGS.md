# Build a combined fixes + v0.29.0 tuning image

[Deutsche Anleitung](BUILD_WITH_TUNINGS.de.md)

This procedure builds one local image containing the five published FP8 W8A8
GEMM tuning files for `Qwen/Qwen3.8-27B-FP8` on two AMD Radeon AI PRO R9700
cards, followed by the AITER LDS fix and both ROCr backoffs.

> **Known trade-off:** On the documented setup, the null-event backoff lowered
> CPU use in the problematic wait path but reproducibly reduced long-response
> decode throughput from roughly 55–58 to 41–44 tok/s. The combined build still
> contains this workaround, and no separate replacement image is provided. See
> [KNOWN_PERFORMANCE_TRADEOFF.md](KNOWN_PERFORMANCE_TRADEOFF.md) for details.

The order matters: build the tuning layer from the immutable upstream image
first, then use that local image as the base for this repository's three
general fixes.

## Quick start

After cloning this repository, run on the R9700 host:

```bash
sudo bash scripts/build-with-tunings.sh
```

The script automatically switches to the `vllm` account, extracts the bundled
and strictly setup-bound tuning archive into a temporary directory, verifies
its five files, builds both image layers, and runs final static verification.
To include the R9700 HIP smoke test, use:

```bash
sudo env GPU_TEST=1 bash scripts/build-with-tunings.sh
```

The resulting image is
`localhost/vllm-r9700:qwen38-v0.29.0-tuned-fixes`.

Alternatively, explicitly select the separate Git branch or an existing
checkout:

```bash
sudo env TUNING_SOURCE=git \
  TUNING_REPO=git@github.com:FA85/r9700-vllm-tuning.git \
  bash scripts/build-with-tunings.sh

sudo env TUNING_DIR=/var/lib/vllm/r9700-vllm-tuning \
  bash scripts/build-with-tunings.sh
```

The sections below document the same process step by step.

## Requirements

- Linux x86-64 with Bash, Git, Python 3, and Podman
- enough storage for the vLLM base image and ROCr build
- a `vllm` user with working rootless Podman
- access to
  [`FA85/r9700-vllm-tuning`](https://github.com/FA85/r9700-vllm-tuning) only
  for the manual Git-based procedure documented below
- two R9700 cards plus `/dev/kfd` and `/dev/dri` for runtime verification

Use the same account for every Podman command. The commands below consistently
use `sudo -u vllm -H` so both build layers share one image store.

## 1. Check out both repositories

```bash
sudo install -d -o vllm -g vllm /var/lib/vllm

sudo -u vllm -H git clone \
  --branch codex/v0.29.0-tuning \
  git@github.com:FA85/r9700-vllm-tuning.git \
  /var/lib/vllm/r9700-vllm-tuning

sudo -u vllm -H git clone \
  https://github.com/FA85/r9700-vllm-rocm72-fixes.git \
  /var/lib/vllm/r9700-vllm-rocm72-fixes
```

For existing checkouts, update them instead:

```bash
sudo -u vllm -H git -C /var/lib/vllm/r9700-vllm-tuning pull --ff-only
sudo -u vllm -H git -C /var/lib/vllm/r9700-vllm-rocm72-fixes pull --ff-only
```

## 2. Verify the published tuning files

```bash
sudo -u vllm -H python3 \
  /var/lib/vllm/r9700-vllm-tuning/r9700-tuning/scripts/verify_published_configs.py
```

The check must report five files and 90 M profiles in total. It validates
structure and SHA-256 values; it does not run a new benchmark.

## 3. Build the tuning image

```bash
sudo -u vllm -H bash \
  /var/lib/vllm/r9700-vllm-tuning/r9700-tuning/scripts/build_tuned_vllm_image.sh \
  --root /var/lib/vllm/r9700-vllm-tuning/r9700-tuning \
  --image docker.io/vllm/vllm-openai-rocm@sha256:e5e47f6aaab675c252c381f0dac237b31b10d87bb74d092b07fb4065efd7f5a1 \
  --model Qwen/Qwen3.8-27B-FP8 \
  --tp-size 2 \
  --tag localhost/vllm-r9700:qwen38-v0.29.0-tuned
```

This uses the published tuning set. Re-running the multi-hour tuner is not
required merely to reproduce the image.

## 4. Build the three fixes on top

```bash
sudo -u vllm -H env \
  BASE_IMAGE=localhost/vllm-r9700:qwen38-v0.29.0-tuned \
  IMAGE=localhost/vllm-r9700:qwen38-v0.29.0-tuned-fixes \
  bash /var/lib/vllm/r9700-vllm-rocm72-fixes/scripts/build.sh
```

The script recognizes the local tuning image, builds ROCr, copies only the
patched library into the final image, and runs static verification of all
three fixes.

## 5. Verify the combined image

```bash
sudo -u vllm -H env \
  IMAGE=localhost/vllm-r9700:qwen38-v0.29.0-tuned-fixes \
  GPU_TEST=1 \
  bash /var/lib/vllm/r9700-vllm-rocm72-fixes/scripts/verify.sh

sudo -u vllm -H podman run --rm --pull=never \
  --entrypoint python3 \
  localhost/vllm-r9700:qwen38-v0.29.0-tuned-fixes \
  -c 'import importlib.util; from pathlib import Path; root=Path(importlib.util.find_spec("vllm").origin).resolve().parent; print(Path("/opt/r9700-tuning/metadata.json").read_text()); print(*sorted((root / "model_executor/layers/quantization/utils/configs").glob("*AMD_Radeon_R9700*")), sep="\n")'
```

The first command must report all three fixes and the HIP smoke test as
`PASS`. The second displays the embedded tuning metadata and five R9700 config
files.

## 6. Start vLLM

Create persistent cache directories:

```bash
sudo install -d -o vllm -g vllm \
  /var/lib/vllm/huggingface \
  /var/lib/vllm/vllm-0.29.0-cache/vllm \
  /var/lib/vllm/vllm-0.29.0-cache/triton \
  /var/lib/vllm/vllm-0.29.0-cache/torchinductor
```

Start the server:

```bash
sudo -u vllm -H env XDG_RUNTIME_DIR=/run/user/987 \
  podman run -d --pull=never \
  --name qwen38-0.29.0-tuned-fixes \
  --network host --ipc host \
  --device /dev/kfd --device /dev/dri \
  --group-add keep-groups \
  --security-opt seccomp=unconfined \
  -v /var/lib/vllm/huggingface:/root/.cache/huggingface \
  -v /var/lib/vllm/vllm-0.29.0-cache/vllm:/root/.cache/vllm \
  -v /var/lib/vllm/vllm-0.29.0-cache/triton:/root/.triton \
  -v /var/lib/vllm/vllm-0.29.0-cache/torchinductor:/root/.cache/torchinductor \
  -e TRITON_CACHE_DIR=/root/.triton \
  -e TORCHINDUCTOR_CACHE_DIR=/root/.cache/torchinductor \
  -e HIP_VISIBLE_DEVICES=0,1 \
  -e PYTHONUNBUFFERED=1 \
  -e NCCL_PROTO=Simple \
  -e VLLM_EXECUTE_MODEL_TIMEOUT_SECONDS=1800 \
  localhost/vllm-r9700:qwen38-v0.29.0-tuned-fixes \
  Qwen/Qwen3.8-27B-FP8 \
    --port 8001 \
    --tensor-parallel-size 2 \
    --kv-cache-memory-bytes 5000000000 \
    --max-num-seqs 4 \
    --max-model-len 131072 \
    --max-num-batched-tokens 9216 \
    --gpu-memory-utilization 0.9 \
    --mamba-cache-mode none \
    --enable-auto-tool-choice \
    --tool-call-parser qwen3_coder \
    --reasoning-parser qwen3 \
    --speculative-config '{"method":"mtp","num_speculative_tokens":2}' \
    --enable-per-request-metrics \
    --enable-prompt-tokens-details \
    --per-request-spec-decode-metrics summary
```

Replace `987` with the actual UID reported by `id -u vllm` if it differs.

Check the server with:

```bash
curl -fsS http://127.0.0.1:8001/v1/models
sudo -u vllm -H env XDG_RUNTIME_DIR=/run/user/987 \
  podman logs --tail 100 qwen38-0.29.0-tuned-fixes
```

The command above follows the published tuning contract and lets vLLM select
the attention backend. To explicitly exercise the patched AITER LDS path, also
insert

```bash
-e VLLM_ROCM_USE_AITER=1
```

before the image name and

```bash
--attention-backend ROCM_AITER_UNIFIED_ATTN
```

after the model name. Test this mode separately with identical prompts against
the default backend. MTP may provide a gain or add overhead depending on the
attention backend and workload, so measure the AITER run both with and without
`--speculative-config`.

## Version boundary

The tuning and fixes apply only to the pinned vLLM 0.29.0 / ROCm 7.2 base.
A different image digest, model, GPU, or vLLM/AITER/ROCr version requires new
compatibility checks, tuning, and patch review. Do not bypass the digest or
checksum guards.
