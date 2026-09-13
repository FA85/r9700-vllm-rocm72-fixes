# Third-party notices

The MIT license in this repository covers the original build, verification,
and patch-application scripts. It does not replace the licenses of the base
image or the source files and binaries modified or redistributed by the build.
The authorship wording in [DISCLAIMER.md](DISCLAIMER.md) applies only to this
original project code and makes no claim over the third-party works below.

## vLLM

- Project: <https://github.com/vllm-project/vllm>
- Base image: `docker.io/vllm/vllm-openai-rocm:v0.29.0`
- Pinned digest:
  `sha256:e5e47f6aaab675c252c381f0dac237b31b10d87bb74d092b07fb4065efd7f5a1`
- License: Apache License 2.0
- License text: <https://github.com/vllm-project/vllm/blob/main/LICENSE>

The resulting container retains all components and notices shipped by that
base image.

## AMD AITER

- Project: <https://github.com/ROCm/aiter>
- Relevant upstream work: <https://github.com/ROCm/aiter/pull/5035>
- Referenced commit: `bb21649`
- Installed version patched by this build: `amd-aiter 0.1.19`
- License: MIT; reproduced in `licenses/AITER-MIT.txt`

The patch application modifies AITER's installed
`ops/triton/attention/unified_attention.py`; the modified upstream code remains
subject to AITER's license.

## ROCr runtime / ROCm Systems

- Project: <https://github.com/ROCm/rocm-systems>
- Exact source used by the known ROCm 7.2.3 image build:
  <https://github.com/mawong-amd/rocm-systems/commit/c7e40e16bca10311af72aee09cfa0cd1726f70a7>
- AsyncEventsLoop upstream fix:
  <https://github.com/ROCm/rocm-systems/pull/7898>
- Upstream fix commit: `46558b7af4dc79b8b8014619c1afdb82db079a9f`
- License: University of Illinois/NCSA; reproduced in
  `licenses/ROCR-NCSA.txt`

The build modifies ROCr source and redistributes a rebuilt, stripped
`libhsa-runtime64.so.1.18.0`. ROCr source and that derived binary remain
subject to the notices and license in the pinned upstream source tree.

## Trademarks and endorsement

AMD, Radeon, ROCm, AITER, vLLM, and other names belong to their respective
owners. This project is unofficial and is not endorsed by AMD or the upstream
projects.
