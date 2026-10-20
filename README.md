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

> **Known trade-off:** The null-event backoff lowers CPU use in the problematic
> wait path, but caused a reproducible long-response decode regression from
> roughly 55–58 to 41–44 tok/s on the documented setup. This repository
> intentionally provides no separate replacement image without that backoff.
> See the [measurements and scope](KNOWN_PERFORMANCE_TRADEOFF.md).

> **Upgrade policy (2026-10-12):** This project deliberately skips vLLM
> 0.30.0 and 0.31.0 and is waiting for v0.32.0 as the next evaluation point.
> The working v0.29.0 production stack is not being replaced by a release that
> neither removes all local ROCr workarounds nor demonstrates a reproducible
> benefit for this exact dual-R9700, dense-Qwen3.8 FP8 setup.
> The latest release published from this repository has run continuously,
> stably, and without observed faults on the author's system since publication.
> Current nightlies contain relevant GDN/MTP correctness fixes and an opt-in
> RDNA4 segmented-attention backend. A first isolated dual-R9700 test now shows
> that the stock nightly starts successfully and that segmented attention is a
> measurable performance candidate, but this is not yet a production-stability
> validation. v0.32.0 therefore remains a checkpoint for isolated testing, not
> a promised upgrade.
> **Update from 2026-10-16:** A preliminary source review
> suggests that all three existing patches may initially be omitted; only the
> still-open `rocprofiler-sdk` signal-pool fix remains a conditional candidate
> if the stock v0.32 image actually reproduces KFD event exhaustion. See the
> [v0.30/v0.31 skip decision and v0.32 watchlist](UPGRADE_WATCH.md).

> **Update from 2026-10-20 — no successor image planned:** The tested stock
> nightly now contains the upstream RDNA unified-attention LDS guard, including
> `gfx1201`, so the local AITER 0.1.19 LDS backport is no longer required. On
> this dual-R9700 setup, starting the otherwise unmodified image with
> `HSA_TOOLS_DISABLE_REGISTER=1` also avoided the persistent idle-CPU behavior
> that motivated both local ROCr backoffs. The accompanying throughput and
> replay checks showed no performance loss attributable to this setting. It
> disables HSA tool/profiler registration and must therefore be removed for
> profiling sessions; this is a setup-specific operational workaround, not an
> upstream runtime fix. Because these two changes make all three local source
> patches unnecessary for the tested nightly, this repository will **not
> publish a new patched image release** for that line. The existing v0.29.0
> release remains available as a historical, version-pinned solution. See the
> [updated upgrade note](UPGRADE_WATCH.md).

## Preliminary stock-nightly result (2026-10-16)

The unmodified official image
`vllm/vllm-openai-rocm:nightly-49cb2bbf71cfd36ee5aa33d1e184b1cddff55294`
starts and serves `Qwen/Qwen3.8-27B-FP8` on two R9700 GPUs with TP=2, MTP=2,
a 131,072-token model limit, and the previous 5,000,000,000-byte KV-cache
allocation. No local patch or published GEMM tuning file was present in these
runs.

A 25-request local comparison produced the following medians. Decode and
aggregate throughput are tokens/s; TTFT is seconds.

| Case | Metric | AITER unified | Segmented static | Segmented tuned |
| --- | --- | ---: | ---: | ---: |
| Single decode | Decode | 48.57 | 50.04 | 50.07 |
| Single decode | TTFT | 0.078 | 0.122 | 0.130 |
| Long context, cold | Decode | 50.16 | 52.24 | 52.28 |
| Long context, cold | TTFT | 8.485 | 12.458 | 12.755 |
| Long context, warm | Decode | 50.21 | 52.21 | 52.35 |
| Long context, warm | TTFT | 0.673 | 0.345 | 0.336 |
| Concurrent requests | Aggregate | 110.93 | 149.78 | 152.64 |
| Concurrent requests | TTFT | 2.673 | 1.393 | 1.332 |

Relative to AITER unified, tuned `ROCM_SEGMENTED_ATTN` delivered about 3.1%
more single-request decode throughput, 4.2-4.3% more long-context decode
throughput, and 37.6% more aggregate concurrent throughput. Its cold
long-context and single-request TTFT were worse, while warm long-context and
concurrent TTFT improved. Autotuning added only 0.1-1.9% over static segmented
attention in this run, apart from small TTFT movement.

These results are preliminary, not a release qualification. Output hashes
differed for all 25 AITER-versus-tuned responses; kernel-dependent rounding
can change sampled output, but the contents still require review before any
correctness claim. The stock nightly also returned to roughly 200% idle CPU
use after initialization. That confirms the idle-load symptom remains in this
configuration, but does not by itself establish KFD-event exhaustion or its
root cause. DFlash2 was not part of these measurements and is being evaluated
separately.

This repository builds an unofficial derivative of the official vLLM ROCm
image for AMD Radeon AI PRO R9700 (`gfx1201`). It contains exactly three
targeted changes:

1. **AITER LDS guard** — a minimal `amd-aiter 0.1.19` backport inspired by
   [ROCm/aiter#5035](https://github.com/ROCm/aiter/pull/5035), keeping the
   unified-attention 3D configuration within the 64 KiB LDS budget on
   `gfx1201`.
2. **ROCr AsyncEventsLoop backoff** — a backport of
   [ROCm/rocm-systems#7898](https://github.com/ROCm/rocm-systems/pull/7898),
   merged upstream as
   [`46558b7`](https://github.com/ROCm/rocm-systems/commit/46558b7af4dc79b8b8014619c1afdb82db079a9f),
   preventing a signal-polling fallback from occupying one CPU core. The later
   native-Linux mixed-batch correction is upstream commit
   [`867d8de`](https://github.com/ROCm/rocm-systems/commit/867d8def53f68bbb892b4fd5605eff727eab6c0f)
   from [ROCm/rocm-systems#13149](https://github.com/ROCm/rocm-systems/pull/13149).
3. **ROCr null-event backoff** — a narrowly scoped workaround for a blocked
   `InterruptSignal` without a KFD event. It polls the userspace signal with an
   exponential 20–200 microsecond sleep instead of repeatedly calling
   `hsaKmtWaitOnEvent_Ext(nullptr, ...)` and receiving `INVALID_HANDLE`. This
   lowers the observed idle CPU load but carries a
   [documented decode regression](KNOWN_PERFORMANCE_TRADEOFF.md).

It deliberately contains no model-specific GEMM tuning, HIP `LD_PRELOAD`
hook, hybrid/true-blocking wait experiment, debug symbol bundle, or
`SYS_PTRACE` requirement.

The model-specific tuning remains in the separate
[`r9700-vllm-tuning`](https://github.com/FA85/r9700-vllm-tuning) repository.
To build one local image containing both that v0.29.0 tuning and these three
fixes, follow [Build with v0.29.0 tuning](BUILD_WITH_TUNINGS.md). The short path
after cloning this repository uses the bundled,
[strictly setup-bound archive](tunings/SETUP_SCOPE.md):

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
merged [ROCm Systems PR #7898](https://github.com/ROCm/rocm-systems/pull/7898)
and its official merge commit
[`46558b7`](https://github.com/ROCm/rocm-systems/commit/46558b7af4dc79b8b8014619c1afdb82db079a9f).
The upstream follow-up for interrupt-capable native-Linux mixed batches is
[`867d8de`](https://github.com/ROCm/rocm-systems/commit/867d8def53f68bbb892b4fd5605eff727eab6c0f).
Issue #7860 has a different trigger, so it is not evidence that its exact root
cause was the same as in our vLLM case. The additional null-event path was
separately traced in our setup to `InterruptSignal::WaitRelaxed` and an invalid
KFD event handle, and remains a local workaround. There is no corresponding
upstream ROCm commit for that additional null-event patch; presenting either
of the two AsyncEventsLoop commits as its source would be inaccurate.

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
general ROCr fix. On this setup it also reduced long-response decode throughput
by a reproducible roughly 20 to 29 percent. The trade-off is documented in
[KNOWN_PERFORMANCE_TRADEOFF.md](KNOWN_PERFORMANCE_TRADEOFF.md).

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for source and licensing
information.
