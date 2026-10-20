# vLLM nightly da913 / ROCm 10 on two R9700 GPUs

[Deutsche README](README.de.md)

This repository now documents two generations of our dual-R9700 setup:

- the historical, locally patched vLLM 0.29.0 / ROCm 7.2 image;
- the currently used, exactly pinned stock ROCm 10.0 nightly, running without
  local source patches.

> Every byte of original project code in this repository was written by
> OpenAI Codex at the direction of and in collaboration with FA85. The project
> started because performance of the then-current stock image was
> unsatisfactory and the power bill caused by idle CPU load was simply too
> high. See the full [disclaimer](DISCLAIMER.md).

## Current operating baseline

We do not simply use the newest nightly, and we are not silently switching to
vLLM 0.32.0. The documented and tested baseline is exactly:

```text
Tag:    nightly-rocm100-da9134bc89364465f68aa679564435936d157a14
Digest: sha256:56d1a901c86f9ca12c98e5efb00467eaebc299378428394ec3afcb45d4635fc3
```

| Component | Configuration in use |
| --- | --- |
| Base image | official unmodified vLLM ROCm nightly at the digest above |
| ROCm | 10.0 |
| GPUs | 2 × AMD Radeon AI PRO R9700 (`gfx1201`) |
| Model | `Qwen/Qwen3.8-27B-FP8` |
| Parallelism | tensor parallelism 2 |
| Attention | `ROCM_SEGMENTED_ATTN` |
| Speculative decoding | MTP with two speculative tokens |
| Model length | 131,072 tokens |
| Local source patches | none |
| Idle-CPU workaround | `HSA_TOOLS_DISABLE_REGISTER=1` |
| Old v0.29 tuning JSONs | not included |

[vLLM 0.32.0](https://github.com/vllm-project/vllm/releases/tag/v0.32.0) has
since been released, but it is newer than this tested pin. The release tag
therefore does not replace the digest documented here without its own
reproduction and stability test.

## Why there is no new patched image

Support and practical stability for `gfx1201` have moved forward noticeably
in only a few weeks:

- the
  [AITER LDS guard](https://github.com/ROCm/aiter/pull/4868) that previously
  required a local patch is now upstream;
- vLLM has an optional RDNA3/RDNA4 backend,
  [`ROCM_SEGMENTED_ATTN`](https://github.com/vllm-project/vllm/pull/59132);
- several relevant Qwen3.8, GDN, prefix-cache, and MTP fixes have landed;
- the pinned stock build above starts and runs on two R9700 GPUs without the
  three former local source patches;
- `HSA_TOOLS_DISABLE_REGISTER=1` prevents the previously observed persistent
  idle CPU load on this system, without performance loss attributable to that
  setting in the accompanying replay and throughput measurements.

The setting disables HSA tool and profiler registration. Remove it when using
`rocprof`, ROCProfiler, or similar tools. It is a setup-specific operational
workaround, not proof that the underlying ROCr path has been fixed in general.

Because the AITER fix is upstream and the two ROCr backoffs are no longer
needed for ordinary operation, no new patched image will be published for
this nightly baseline. The existing v0.29.0 release remains available as a
historical, strictly pinned solution and has run continuously, stably, and
without observed faults on the author's system since publication.

## From host to running container

The steps below use the exact digest above, rootless Podman storage owned by
the `vllm` user, two R9700 GPUs, and separate nightly/ROCm-10 compiler caches.
The Hugging Face model cache may be shared with the old setup.

### 1. Create directories

```bash
VLLM_UID="$(id -u vllm)"
VLLM_GID="$(id -g vllm)"

sudo install -d -m 0700 -o "$VLLM_UID" -g "$VLLM_GID" \
  "/run/user/$VLLM_UID"

sudo install -d -o "$VLLM_UID" -g "$VLLM_GID" \
  /var/lib/vllm/huggingface \
  /var/lib/vllm/nightly-da913-rocm100-cache/vllm \
  /var/lib/vllm/nightly-da913-rocm100-cache/triton \
  /var/lib/vllm/nightly-da913-rocm100-cache/torchinductor
```

Do not share the vLLM, Triton, or TorchInductor caches with v0.29, ROCm 7.2,
or another nightly.

### 2. Pull the exact stock image

```bash
VLLM_UID="$(id -u vllm)"

sudo -u vllm -H env XDG_RUNTIME_DIR="/run/user/$VLLM_UID" \
  podman pull \
  docker.io/vllm/vllm-openai-rocm@sha256:56d1a901c86f9ca12c98e5efb00467eaebc299378428394ec3afcb45d4635fc3
```

Optionally verify the locally stored digest:

```bash
sudo -u vllm -H env XDG_RUNTIME_DIR="/run/user/$VLLM_UID" \
  podman image inspect \
  docker.io/vllm/vllm-openai-rocm@sha256:56d1a901c86f9ca12c98e5efb00467eaebc299378428394ec3afcb45d4635fc3 \
  --format '{{index .RepoDigests 0}}'
```

### 3. Start the container with the parameters in use

```bash
VLLM_UID="$(id -u vllm)"

sudo -u vllm -H env XDG_RUNTIME_DIR="/run/user/$VLLM_UID" \
  podman run -d \
  --pull=never \
  --name qwen38-nightly-da913-rocm100-stock \
  --network host \
  --ipc host \
  --device /dev/kfd \
  --device /dev/dri \
  --group-add keep-groups \
  --security-opt seccomp=unconfined \
  --log-driver journald \
  --log-opt tag=qwen38-nightly-da913-rocm100-stock \
  -v /var/lib/vllm/huggingface:/root/.cache/huggingface \
  -v /var/lib/vllm/nightly-da913-rocm100-cache/vllm:/root/.cache/vllm \
  -v /var/lib/vllm/nightly-da913-rocm100-cache/triton:/root/.triton \
  -v /var/lib/vllm/nightly-da913-rocm100-cache/torchinductor:/root/.cache/torchinductor \
  -e TRITON_CACHE_DIR=/root/.triton \
  -e TORCHINDUCTOR_CACHE_DIR=/root/.cache/torchinductor \
  -e HIP_VISIBLE_DEVICES=0,1 \
  -e PYTHONUNBUFFERED=1 \
  -e NCCL_PROTO=Simple \
  -e VLLM_EXECUTE_MODEL_TIMEOUT_SECONDS=1800 \
  -e VLLM_ROCM_USE_AITER=1 \
  -e HSA_TOOLS_DISABLE_REGISTER=1 \
  docker.io/vllm/vllm-openai-rocm@sha256:56d1a901c86f9ca12c98e5efb00467eaebc299378428394ec3afcb45d4635fc3 \
  Qwen/Qwen3.8-27B-FP8 \
  --port 8001 \
  --tensor-parallel-size 2 \
  --kv-cache-memory-bytes 5000000000 \
  --max-num-seqs 4 \
  --max-model-len 131072 \
  --max-num-batched-tokens 9216 \
  --gpu-memory-utilization 0.72 \
  --mamba-cache-mode none \
  --attention-backend ROCM_SEGMENTED_ATTN \
  --enable-auto-tool-choice \
  --tool-call-parser qwen3_coder \
  --reasoning-parser qwen3 \
  --speculative-config '{"method":"mtp","num_speculative_tokens":2}' \
  --enable-per-request-metrics \
  --enable-prompt-tokens-details \
  --per-request-spec-decode-metrics summary
```

The first start can take considerably longer because of JIT and Triton
compilation. The fixed 5,000,000,000-byte KV allocation and
`--gpu-memory-utilization 0.72` leave room for the separate 4B model server on
our host. These values are not a universal optimum.

The current default uses the static segmented-attention configuration. The
separately tested autotuning mode is enabled with

```text
--kernel-config.enable_rocm_segmented_attn_autotune=True
```

but is intentionally not part of the standard command above.

### 4. Follow startup and verify the API

Container logs are stored in the journal on this setup:

```bash
sudo journalctl -t qwen38-nightly-da913-rocm100-stock -a -f -o cat
```

After `Uvicorn running`:

```bash
curl -fsS http://127.0.0.1:8001/v1/models

curl -fsS http://127.0.0.1:8001/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "Qwen/Qwen3.8-27B-FP8",
    "messages": [{"role": "user", "content": "Reply with only: OK"}],
    "temperature": 0,
    "max_tokens": 16
  }'
```

Check idle CPU after at least five minutes without requests:

```bash
VLLM_UID="$(id -u vllm)"

sudo -u vllm -H env XDG_RUNTIME_DIR="/run/user/$VLLM_UID" \
  podman top qwen38-nightly-da913-rocm100-stock hpid,pcpu,state,comm
```

### 5. Stop, remove, and restart

```bash
VLLM_UID="$(id -u vllm)"

sudo -u vllm -H env XDG_RUNTIME_DIR="/run/user/$VLLM_UID" \
  podman stop -t 30 qwen38-nightly-da913-rocm100-stock

sudo -u vllm -H env XDG_RUNTIME_DIR="/run/user/$VLLM_UID" \
  podman rm qwen38-nightly-da913-rocm100-stock
```

Then repeat step 3. Model, compiler, and image caches remain intact.

## Measured attention-backend results

In an earlier local 25-request comparison on two R9700 GPUs,
`ROCM_SEGMENTED_ATTN` delivered roughly 3–4% more single-request and
long-context decode throughput than `ROCM_AITER_UNIFIED_ATTN`, and 35–38%
more aggregate throughput with four concurrent requests. Segmented-attention
autotuning added only another 0.1–1.9% over the static variant. TTFT moved in
both directions depending on the case. These are setup-specific measurements,
not general R9700 guarantees.

DFlash2 was evaluated experimentally, but its additional memory use keeps it
outside the current operating profile. We remain on MTP with two speculative
tokens.

## Tuning files

The five published FP8 GEMM tuning files were measured for vLLM 0.29.0,
ROCm 7.2, and the corresponding AITER/Triton stack. They are not copied into
the ROCm 10 nightly. Nightly tuning must be remeasured against the exact image
digest above, built into a separate image, and compared with stock using
identical requests. Reusing old JSON files only because the model and GPU
names match would not be methodologically valid.

## Historical v0.29.0 patch set

The original image contained:

1. the AITER LDS backport for `gfx1201`;
2. the ROCr AsyncEventsLoop backoff;
3. the local ROCr null-event backoff.

The official ROCr commits associated with the historical AsyncEventsLoop
backport are
[`46558b7`](https://github.com/ROCm/rocm-systems/commit/46558b7af4dc79b8b8014619c1afdb82db079a9f)
and the Linux follow-up
[`867d8de`](https://github.com/ROCm/rocm-systems/commit/867d8def53f68bbb892b4fd5605eff727eab6c0f).
There is no corresponding upstream commit for the additional local null-event
backoff. Its reproducible decode cost is documented in
[KNOWN_PERFORMANCE_TRADEOFF.md](KNOWN_PERFORMANCE_TRADEOFF.md).

The old artifacts remain intentionally available:

- [v0.29.0 build with tuning](BUILD_WITH_TUNINGS.md)
- [upgrade and source chronology](UPGRADE_WATCH.md)
- [third-party and license notices](THIRD_PARTY_NOTICES.md)

`Containerfile`, `patches/`, and the existing build scripts apply only to the
historical, strictly pinned v0.29.0 release. They are not patches for the
current nightly pin.

## Scope

This is an independent experience and reproduction report, not an official
AMD, ROCm, AITER, Qwen, or vLLM package. The parameters were derived on
exactly two R9700 GPUs with the stated model and TP=2. Different drivers,
firmware, models, quantization formats, GPU topology, or parallelism can
produce different results.
