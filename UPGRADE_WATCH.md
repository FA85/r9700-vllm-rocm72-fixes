# vLLM upgrade watch: skipping v0.30.0, watching v0.31.x

[Deutsche Fassung](UPGRADE_WATCH.de.md)

Status: 2026-10-02.

This note records a project decision, not a general recommendation for all
ROCm users. The reference setup is:

- two AMD Radeon AI PRO R9700 GPUs (`gfx1201`), tensor parallelism 2;
- `Qwen/Qwen3.8-27B-FP8`, a dense block-scaled FP8 model;
- the pinned vLLM 0.29.0 / ROCm 7.2.3 image used by this repository;
- AITER unified attention, five locally measured GEMM tuning files, and MTP
  with two speculative tokens;
- the three local fixes documented in this repository.

## Why this project skips v0.30.0

The existing v0.29.0 image has been stable in production. v0.30.0 changes the
ROCm software stack substantially, including its TheRock base, PyTorch,
Triton, and AITER versions, but does not provide enough setup-specific evidence
to justify replacing that known-good deployment.

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

## What may make v0.31.x interesting

No stable v0.31.x release existed when this note was written. The items below
are post-v0.30 work on `main` or open pull requests. An open pull request is not
a promise that the change will ship in v0.31.x.

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

A future stable v0.31.x should be tested in isolation, not installed over the
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
production and use any v0.31.x development image only as a separate lab image.
