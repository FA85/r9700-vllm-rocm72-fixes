# vLLM upgrade watch: skipping v0.30.0/v0.31.0, waiting for v0.32.0

[Deutsche Fassung](UPGRADE_WATCH.de.md)

Status: 2026-10-12.

This note records a project decision, not a general recommendation for all
ROCm users. The reference setup is:

- two AMD Radeon AI PRO R9700 GPUs (`gfx1201`), tensor parallelism 2;
- `Qwen/Qwen3.8-27B-FP8`, a dense block-scaled FP8 model;
- the pinned vLLM 0.29.0 / ROCm 7.2.3 image used by this repository;
- AITER unified attention, five locally measured GEMM tuning files, and MTP
  with two speculative tokens;
- the three local fixes documented in this repository.

## Current decision: wait for v0.32.0

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

Two open pull requests remain especially important after the observed
`hipErrorIllegalAddress` in the ROCm GDN path:

- [vLLM #51508](https://github.com/vllm-project/vllm/pull/51508) describes an
  async-scheduling stale-row condition where an accepted count of zero becomes
  index `-1`; depending on allocation layout it can silently corrupt state or
  cause an illegal memory access.
- [vLLM #50021](https://github.com/vllm-project/vllm/pull/50021) adds upper and
  lower bounds to accepted-token-derived GDN/KDA state lookups. It explicitly
  distinguishes this bounds problem from the still-separate non-`align`
  async-scheduling ordering race.

Because those two crash-near changes are not merged, a current nightly is
interesting for laboratory reproduction but is not yet a clean production
successor. The opt-in native RDNA3/RDNA4 all-reduce
([vLLM #57767](https://github.com/vllm-project/vllm/pull/57767)) and the fix
that makes the AITER unified-attention switch effective on RDNA
([vLLM #56040](https://github.com/vllm-project/vllm/pull/56040)) also remain
open.

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

## Status of the three local fixes

| Local change | Upstream status | Upgrade consequence |
| --- | --- | --- |
| AITER LDS guard | A broader fix is merged in AITER 0.1.23 via [ROCm/aiter #4868](https://github.com/ROCm/aiter/pull/4868). | Candidate for removal after direct validation. |
| ROCr AsyncEventsLoop backoff | [ROCm/rocm-systems #7898](https://github.com/ROCm/rocm-systems/pull/7898) is merged upstream. | Verify that the exact ROCr source used by the release image contains it before dropping the backport. |
| ROCr null-event backoff | No equivalent upstream fix has been identified. [ROCm/rocm-systems #11170](https://github.com/ROCm/rocm-systems/pull/11170) addresses `BusyWaitSignal`, not this exhausted-event/`InterruptSignal` path. | Keep treating it as a local workaround with the documented decode trade-off. |

## Tuning migration rule

The five v0.29.0 tuning JSON files are evidence only for the pinned v0.29.0
stack. For a v0.31.x candidate:

1. determine which GEMM backend actually receives each model shape;
2. determine whether a new native HIP or FlyDSL path bypasses the old AITER
   tuning lookup;
3. rerun every tuned shape against the new default on both GPUs;
4. repeat CUDA/HIP-graph and TP=2 stress tests;
5. publish new tuning files only if they still win reproducibly.

Copying the old files into a new image is not a valid benchmark or migration.

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
