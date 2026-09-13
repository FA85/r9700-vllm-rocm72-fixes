# Minimal R9700 fixes for vLLM 0.29.0 / ROCm 7.2

[Deutsche Anleitung](README.de.md)

> Disclaimer: Every byte of original project code in this repository was
> written by various ChatGPT Codex models; I just navigated. It cost me several
> weeks of investigating and testing. The project grew out of my unhappiness
> with the standard image's performance (9.6 tok/s at 50% KV, leading to the
> AITER LDS patch) and its power consumption when no work was being done
> (leading to the ROCr AsyncEventsLoop and null-event backoffs — I have to pay
> my power bill myself). The resulting setup runs at 50–70 tok/s on my dual
> R9700 system. These are setup-specific observations, not a standardized
> benchmark. See the full [authorship and motivation disclaimer](DISCLAIMER.md).

This repository builds an unofficial derivative of the official vLLM ROCm
image for AMD Radeon AI PRO R9700 (`gfx1201`). It contains exactly three
targeted changes:

1. **AITER LDS guard** — a minimal `amd-aiter 0.1.19` backport inspired by
   [ROCm/aiter#5035](https://github.com/ROCm/aiter/pull/5035), keeping the
   unified-attention 3D configuration within the 64 KiB LDS budget on
   `gfx1201`.
2. **ROCr AsyncEventsLoop backoff** — a backport of
   [ROCm/rocm-systems#7898](https://github.com/ROCm/rocm-systems/pull/7898),
   preventing a signal-polling fallback from occupying one CPU core.
3. **ROCr null-event backoff** — a narrowly scoped workaround for a blocked
   `InterruptSignal` without a KFD event. It polls the userspace signal with an
   exponential 20–200 microsecond sleep instead of repeatedly calling
   `hsaKmtWaitOnEvent_Ext(nullptr, ...)` and receiving `INVALID_HANDLE`.

It deliberately contains no model-specific GEMM tuning, HIP `LD_PRELOAD`
hook, hybrid/true-blocking wait experiment, debug symbol bundle, or
`SYS_PTRACE` requirement.

The model-specific tuning remains in the separate
[`r9700-vllm-tuning`](https://github.com/FA85/r9700-vllm-tuning) repository.
To build one local image containing both that v0.29.0 tuning and these three
fixes, follow [Build with v0.29.0 tuning](BUILD_WITH_TUNINGS.md). The short path
after cloning this repository is:

```bash
sudo bash scripts/build-with-tunings.sh
```

## Diagnostic leads and prior work

This solution did not emerge in isolation. The
[AITER LDS PR #5035](https://github.com/ROCm/aiter/pull/5035) localized the
gfx1201 startup failure to a 3D unified-attention configuration above the
64 KiB LDS limit and provided the basis for the guard backported here to
`amd-aiter 0.1.19`.

For the idle-load problem, the independently published
[ROCm Systems issue #7860](https://github.com/ROCm/rocm-systems/issues/7860)
had already identified the same hot HSA/ROCr location,
`Runtime::AsyncEventsLoop`. That was an important lead for our profiler and
debugger work. The AsyncEventsLoop patch itself follows the subsequently
merged [ROCm Systems PR #7898](https://github.com/ROCm/rocm-systems/pull/7898).
Issue #7860 has a different trigger, so it is not evidence that its exact root
cause was the same as in our vLLM case. The additional null-event path was
separately traced in our setup to `InterruptSignal::WaitRelaxed` and an invalid
KFD event handle, and remains a local workaround.

## Version scope

The build is intentionally pinned and fails closed when its assumptions do not
match:

- base image: `vllm/vllm-openai-rocm:v0.29.0`
- base digest:
  `sha256:e5e47f6aaab675c252c381f0dac237b31b10d87bb74d092b07fb4065efd7f5a1`
- ROCm: 7.2.3
- ROCr library: `libhsa-runtime64.so.1.18.0`
- expected original library SHA-256:
  `bec3c44c469d79c79c70bded96ac1c88d1c5c5e0e4b7abfa26096029075090f7`
- ROCr source commit: `c7e40e16bca10311af72aee09cfa0cd1726f70a7`
- amd-aiter: 0.1.19 as supplied by the pinned base image

Do not remove these checks to make a newer image build. Rebase and validate the
patches against the new upstream source instead.

## Build

Requirements: Linux x86-64, Bash, Git, and Podman (Docker can be selected with
`CONTAINER_TOOL=docker`). A GPU is not required to build, but the runtime test
must run on the target R9700 host. The ROCm base image and build stages require
substantial disk space.

```bash
git clone https://github.com/FA85/r9700-vllm-rocm72-fixes.git
cd r9700-vllm-rocm72-fixes
bash scripts/build.sh
```

To choose another local tag:

```bash
IMAGE=localhost/r9700-vllm:my-test bash scripts/build.sh
```

The build uses the pinned official base and produces
`localhost/r9700-vllm:v0.29.0-rocm72-minimal-fixes` by default. Only the
patched, stripped ROCr library is copied from the compiler stage into the final
image.

## Verify

Static image verification is part of `build.sh` and can be repeated with:

```bash
bash scripts/verify.sh
```

On an R9700 host, add the HIP device smoke test:

```bash
GPU_TEST=1 bash scripts/verify.sh
```

The verification checks all three fix labels and markers, confirms that ROCr
was replaced, and rejects the diagnostic/experimental additions listed above.
It does not replace a real vLLM request, throughput test, or latency comparison.

## Run vLLM

The image keeps the upstream vLLM entrypoint. A small Podman example is
included; all arguments after the script name are passed to vLLM:

```bash
HF_CACHE=/var/lib/vllm/huggingface \
  bash scripts/run-example.sh \
  --port 8001 \
  --max-model-len 131072 \
  --max-num-seqs 4
```

The defaults use `Qwen/Qwen3.8-27B-FP8`, two visible GPUs, tensor parallelism
2, and `NCCL_PROTO=Simple`. Override `MODEL`, `HIP_VISIBLE_DEVICES`,
`TENSOR_PARALLEL_SIZE`, or `NCCL_PROTO` as environment variables. Model
compatibility is otherwise inherited from the pinned vLLM image.

## Publish to GHCR

The workflow in `.github/workflows/publish.yml` builds and pushes on a `v*`
tag or manual dispatch. It targets a self-hosted Linux x86-64 runner because
the base image and ROCr build are large. The runner needs Bash and Podman; it
does not need a GPU for the build.

```bash
git tag v0.1.0
git push origin v0.1.0
```

This publishes
`ghcr.io/fa85/r9700-vllm-rocm72-fixes:v0.1.0`. Run `GPU_TEST=1` against that
exact tag on an R9700 host before describing it as runtime-tested. Package
visibility may need to be changed to public once in the GitHub Packages UI.

## Status and risk

The three changes were isolated through CPU profiling and debugger probes on a
two-R9700 vLLM deployment. They fixed the observed AITER LDS failure and idle
CPU spinning in that setup. This is still an unofficial compatibility image,
not an AMD, ROCm, AITER, or vLLM release. In particular, the null-event backoff
is a local workaround and should be reviewed upstream before being treated as a
general ROCr fix.

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for source and licensing
information.
