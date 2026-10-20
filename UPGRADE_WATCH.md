# vLLM upgrade watch: v0.32.0 and the tested post-v0.31 nightly

[Deutsche Fassung](UPGRADE_WATCH.de.md)

Status: 2026-10-12; updated on 2026-10-16 with the preliminary v0.32 patch and
tuning plan and on 2026-10-20 with the tested patch-retirement decision.

This note records a project decision, not a general recommendation for all
ROCm users. The reference setup is:

- two AMD Radeon AI PRO R9700 GPUs (`gfx1201`), tensor parallelism 2;
- `Qwen/Qwen3.8-27B-FP8`, a dense block-scaled FP8 model;
- the pinned vLLM 0.29.0 / ROCm 7.2.3 image used by this repository;
- AITER unified attention, five locally measured GEMM tuning files, and MTP
  with two speculative tokens;
- the three local fixes documented in this repository.

## Update 2026-10-20: no new patched image release

The tested stock nightly has moved this project beyond the three local source
patches:

- its AITER version contains the upstream
  [RDNA unified-attention LDS guard](https://github.com/ROCm/aiter/pull/4868),
  including `gfx1201`, replacing the local AITER 0.1.19 backport;
- setting `HSA_TOOLS_DISABLE_REGISTER=1` on the otherwise unmodified image
  avoided the persistent idle-CPU behavior that motivated both local ROCr
  backoffs;
- the accompanying throughput and historical-request replay checks found no
  performance loss attributable to that setting on the reference setup.

`HSA_TOOLS_DISABLE_REGISTER=1` disables HSA tool and profiler registration. It
must be removed when ROCm/HSA profiling is required, and this result must not
be read as a general ROCr fix or a guarantee for other applications. For this
repository's normal inference workload, however, the upstream LDS guard plus
that runtime setting make all three local binary/source patches unnecessary.

Consequently, this repository will **not publish a new patched container image
for the tested nightly line**. The existing v0.29.0 release remains available
as a historical, version-pinned solution for the stack it documents. Any
future image publication would require a new, reproducible problem that again
needs an actual source change; a higher vLLM version alone is not sufficient.

## Previous decision before the v0.32.0 release

v0.31.0 is now stable, but this project will not move its production image to
it. The next evaluation point is v0.32.0. This is not a promise to upgrade:
v0.32.0 must still pass the setup-specific gate below in an isolated image.

The reason for waiting is now stronger than simple version conservatism:

- [vLLM #56531](https://github.com/vllm-project/vllm/pull/56531), merged after
  the v0.31.0 release cut, keeps speculation-capable hybrid recurrent rows on a
  consistent state path, including zero-draft steps.
- [vLLM #55504](https://github.com/vllm-project/vllm/pull/55504), merged on
  2026-10-10, prevents oversized GDN decode rows from entering a bounded
  speculative-state layout. Both changes are directly relevant to hybrid GDN
  models with speculative decoding.
- [vLLM #55601](https://github.com/vllm-project/vllm/pull/55601) and
  [vLLM #60533](https://github.com/vllm-project/vllm/pull/60533) fix hybrid
  Mamba/GDN prefix-cache state indexing and checkpoint-boundary errors. Their
  published trigger cases include DFlash2/EAGLE layouts, so applicability to
  this exact MTP configuration must still be demonstrated.
- [vLLM #59132](https://github.com/vllm-project/vllm/pull/59132) adds an
  opt-in `ROCM_SEGMENTED_ATTN` backend for RDNA3/RDNA4 and includes a direct
  dual-R9700, TP=2, `Qwen/Qwen3.8-27B-FP8` comparison. That makes it a serious
  lab candidate, but not yet evidence that it beats this repository's tuned
  production stack under identical requests and cache settings.
- [vLLM #57560](https://github.com/vllm-project/vllm/pull/57560) adds an
  opt-in AITER FlyDSL GDN prefill path. It was validated on MI355X with a much
  larger Qwen3.8 model, not on `gfx1201` with this dense 27B checkpoint.

Other open changes include the opt-in native RDNA3/RDNA4 all-reduce
([vLLM #57767](https://github.com/vllm-project/vllm/pull/57767)) and the fix
that makes the AITER unified-attention switch effective on RDNA
([vLLM #56040](https://github.com/vllm-project/vllm/pull/56040)). Open pull
requests are not a basis for production approval; the isolated test of a stable
release image remains decisive.

## Why this project skips v0.30.0

The existing v0.29.0 image has been stable in production. The latest release
published from this repository has run continuously, stably, and without
observed faults on the author's system since publication. This is a report
about that specific deployment, not a general stability guarantee. v0.30.0
changes the ROCm software stack substantially, including its TheRock base,
PyTorch, Triton, and AITER versions, but does not provide enough setup-specific
evidence to justify replacing that known-good deployment.

In particular:

- v0.30.0 does not provide a verified complete replacement for both local ROCr
  workarounds. The null-event workaround remains local.
- v0.30.0 pins AITER 0.1.21.post2, before the broader upstream RDNA LDS guard
  released in AITER 0.1.23.
- The five published GEMM tuning files were measured against the pinned
  v0.29.0 stack. A different AITER/Triton/kernel router may accept the files
  syntactically while making their performance conclusions invalid.
- Most v0.30.0 ROCm headline work targets CDNA, MoE, sparse-attention, or other
  models and must not be transferred to dense Qwen3.8-27B-FP8 without a direct
  measurement.

The decision is therefore **skip**, not "v0.30.0 is broken." It may be useful
for other hardware and workloads; it simply does not clear this project's
upgrade threshold.

## What originally made v0.31.x interesting

The items below were the original post-v0.30 watchlist. They remain useful
historical context, but the current decision and post-v0.31 nightly status are
recorded above. An open pull request is not a promise that it will ship in
v0.32.0.

### Already on vLLM main

- **AITER 0.1.23:**
  [vLLM #58867](https://github.com/vllm-project/vllm/pull/58867) merged the
  version bump. AITER 0.1.23 contains the broader upstream
  [RDNA unified-attention LDS guard](https://github.com/ROCm/aiter/pull/4868),
  including `gfx1201`. This is the first credible upstream replacement for the
  local AITER LDS backport, but it still needs an exact image, model, graph
  capture, long-context, and performance test before the local patch is
  removed.

### Open candidates with direct relevance

- **Native W8A8 FP8 HIP GEMM for gfx1201:**
  [vLLM #58238](https://github.com/vllm-project/vllm/pull/58238) proposes an
  opt-in kernel for prefill and decode. Its published R9700 TP=2 result uses
  Qwen3-32B-FP8 rather than this repository's exact model and reports roughly
  25% lower mean TPOT and 43% lower mean TTFT at concurrency 16. This is highly
  relevant, but not yet a single-request Qwen3.8-27B result.
- **Split-KV decode attention for RDNA3/RDNA4:**
  [vLLM #58156](https://github.com/vllm-project/vllm/pull/58156) targets the
  long-context decode bottleneck and uses Qwen3.8-27B TP=2 shapes. The reported
  4.9x to 19.1x speedups are kernel-only measurements on `gfx1100`, not
  end-to-end R9700 throughput.
- **Native HIP all-reduce for RDNA3/RDNA4:**
  [vLLM #57767](https://github.com/vllm-project/vllm/pull/57767) supports TP=2
  and TP=4 decode on `gfx1201`. Its R9700 end-to-end headline comes from a BF16
  MoE TP=4 workload, so the gain for dense FP8 TP=2 remains unproven.
- **RDNA4 FlyDSL FP8 block-scale GEMMs:**
  [vLLM #56005](https://github.com/vllm-project/vllm/pull/56005) explicitly
  targets `Qwen3.8-27B-FP8` shapes on R9700. All 18 published kernel cases beat
  the Triton baseline, with a 1.786x geometric mean, but no end-to-end serving
  result was reported and FlyDSL is an additional dependency.

These candidates are more interesting than the v0.30.0 version number itself
because they target the actual bottlenecks and hardware in this repository.

## Preliminary v0.32.0 patch plan (2026-10-16)

This assessment concerns the current
[`releases/v0.32.0` branch](https://github.com/vllm-project/vllm/tree/releases/v0.32.0),
not a final release image already validated on this system. The first test will
therefore deliberately use the **unmodified official image**, without any of
the three local patches and initially without the five local GEMM tuning files.
Only a problem reproduced on this exact setup justifies a new patch.

| Previous local change | Status in the current v0.32 branch | Planned treatment |
| --- | --- | --- |
| AITER LDS guard | The branch builds [AITER 0.1.24.post1](https://github.com/vllm-project/vllm/blob/releases/v0.32.0/docker/Dockerfile.rocm_base), which contains the broader RDNA LDS guard from [ROCm/aiter #4868](https://github.com/ROCm/aiter/pull/4868). | Omit the local backport initially and validate cold start plus Unified Attention directly on `gfx1201`. |
| ROCr AsyncEventsLoop backoff | The earlier upstream implementation is commit [`46558b7`](https://github.com/ROCm/rocm-systems/commit/46558b7af4dc79b8b8014619c1afdb82db079a9f). The currently pinned ROCr source does not contain the local 20–200 us backoff, and official follow-up commit [`867d8de`](https://github.com/ROCm/rocm-systems/commit/867d8def53f68bbb892b4fd5605eff727eab6c0f) from [#13149](https://github.com/ROCm/rocm-systems/pull/13149) removes that backoff again on interrupt-capable native Linux because it adds latency to mixed signal batches. | Do not carry it forward. |
| ROCr null-event backoff | This backoff treats the polling symptom and has the documented decode trade-off. One now-identified possible cause is exhaustion of all KFD events by the `rocprofiler-sdk` signal pool. | Do not carry it forward pre-emptively. Test the stock image for idle CPU use and missing events first. |

### Possible remaining root-cause patch

The `rocprofiler-sdk` revision pinned by the v0.32 branch still allocates 4096
interrupt-backed HSA signals when its first pool is created. That equals the
entire per-process KFD event limit and matches this project's observed
`checked_out_highwater=4094` and `create_failure=1` counters.
[ROCm/rocm-systems #13177](https://github.com/ROCm/rocm-systems/issues/13177)
identifies this relationship; the still-open
[root-cause patch #13179](https://github.com/ROCm/rocm-systems/pull/13179)
reduces the pool batch from 4096 to 1024.

**Source readability note:** The upstream value is written as
`constexpr size_t default_signal_pool_size = (1 << 12);`. Although this
produces the same machine value as `4096`, it needlessly obscures the meaning
here: this is a concrete number of reserved signals, not a bit mask or bit
field. Writing `4096` would expose the domain meaning directly and make its
notable equality with the KFD event limit easier to spot during review. The
notation is not evidence of causality by itself, but it makes human review of
exactly this kind of boundary problem harder.

This small `rocprofiler-sdk` change is the only patch candidate currently
visible for v0.32.0. It will nevertheless **not be applied proactively**. Only
if the unmodified release image again shows persistent idle CPU use and event
exhaustion is confirmed should this root-cause patch be tested in isolation.
The two old ROCr backoffs should not be carried into a v0.32 image.

## Tuning migration rule

The five v0.29.0 tuning JSON files are performance evidence only for the pinned
v0.29.0 stack. The
[v0.32 config loader](https://github.com/vllm-project/vllm/blob/releases/v0.32.0/vllm/model_executor/layers/quantization/utils/fp8_utils.py)
still uses the same path, filename, and JSON schema for `fp8_w8a8` with block
shape `[128,128]`, so the files remain mechanically compatible. That does not
prove that the dispatcher selects this kernel path in a particular run or that
the old winners remain optimal under the new PyTorch/Triton/vLLM stack.

The test order is therefore v0.32 without local configs, then the same image
with the five old JSON files, followed by a full retune. During that process:

1. determine which GEMM backend actually receives each model shape;
2. determine whether a new native HIP or FlyDSL path bypasses the old AITER
   tuning lookup;
3. rerun every tuned shape against the new default on both GPUs;
4. repeat CUDA/HIP-graph and TP=2 stress tests;
5. publish new tuning files only if they still win reproducibly.

The old files may serve as compatibility and comparison candidates. Merely
copying them into a new image and publishing them as "v0.32 tuning" is not a
valid benchmark or migration. Optional `ROCM_SEGMENTED_ATTN` also maintains a
separate attention autotuning cache; it is independent of these five GEMM JSON
files.

## Upgrade gate

A future stable v0.32.0 should be tested in isolation, not installed over the
working image. Preparing an upgrade becomes reasonable only after the release
contains materially relevant changes such as those above and passes all of the
following on the exact production host:

- cold start and AITER LDS validation;
- exact historical request replays, including long reasoning responses;
- decode throughput, TTFT, and prefix-cache comparison;
- MTP on/off comparison with the same two-token setting;
- TP=2 correctness and sustained stress;
- idle CPU and power measurements after RCCL initialization;
- verification of which local patches are still required;
- fresh GEMM backend selection and tuning measurements.

Until then, the recommendation for this repository remains: keep v0.29.0 in
production and use any v0.32 development image only as a separate lab image.
