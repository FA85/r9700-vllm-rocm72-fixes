# Strict setup scope / Strikte Setup-Bindung

## Deutsch

**Dieses Archiv ist kein allgemeines R9700-Tuning.** Die enthaltenen
FP8-W8A8-GEMM-Konfigurationen wurden ausschließlich für folgendes Setup
veröffentlicht:

- GPU: zwei AMD Radeon AI PRO R9700 (`gfx1201`)
- Modell: `Qwen/Qwen3.8-27B-FP8`
- Quantisierung: `fp8_w8a8`, Blockgröße `[128,128]`
- Tensor Parallelism: `2`
- vLLM: `0.29.0`
- ROCm/HIP: `7.2.x`
- Basisimage: `docker.io/vllm/vllm-openai-rocm` mit Digest
  `sha256:e5e47f6aaab675c252c381f0dac237b31b10d87bb74d092b07fb4065efd7f5a1`
- produktiver Referenzpfad: vLLM-Standard-Attention-Backend,
  `NCCL_PROTO=Simple` und MTP mit zwei speculative tokens

Verpackt wurde der veröffentlichte Stand aus `FA85/r9700-vllm-tuning`, Branch
`codex/v0.29.0-tuning`, Commit
`a964f2b4f9c0e43879002f700f6da0c7b76c3671`.

Das Archiv enthält fünf GEMM-Formen mit je 18 M-Profilen. Bei der Neumessung
unter der genannten v0.29.0-Basis blieben die vorhandenen Sieger erhalten und
die fünf Dateien damit bytegleich zum Seed. Das Kandidaten-Zeitprotokoll wurde
nicht archiviert. Deshalb wird weder eine konkrete Beschleunigung gegenüber
vLLM-Defaults noch ein Vorteil auf anderen Setups behauptet.

Schon eine andere GPU, ein anderes Modell, TP-Größe, Image-Digest oder eine
andere vLLM-, ROCm-, AITER- oder Triton-Version liegt außerhalb des geprüften
Bereichs. Dort müssen die Konfigurationen neu vermessen und validiert werden.
Die Nutzung erfolgt auf eigenes Risiko und ohne Gewähr.

## English

**This archive is not general-purpose R9700 tuning.** Its FP8 W8A8 GEMM
configurations are published only for this setup:

- GPU: two AMD Radeon AI PRO R9700 cards (`gfx1201`)
- model: `Qwen/Qwen3.8-27B-FP8`
- quantization: `fp8_w8a8`, block shape `[128,128]`
- tensor parallelism: `2`
- vLLM: `0.29.0`
- ROCm/HIP: `7.2.x`
- base image: `docker.io/vllm/vllm-openai-rocm` at digest
  `sha256:e5e47f6aaab675c252c381f0dac237b31b10d87bb74d092b07fb4065efd7f5a1`
- production reference path: vLLM's default attention backend,
  `NCCL_PROTO=Simple`, and MTP with two speculative tokens

The package was created from the published `FA85/r9700-vllm-tuning` branch
`codex/v0.29.0-tuning` at commit
`a964f2b4f9c0e43879002f700f6da0c7b76c3671`.

The archive contains five GEMM shapes with 18 M profiles each. During
remeasurement under the specified v0.29.0 base, all existing winners were
retained, leaving the five files byte-identical to the seed. Per-candidate
timing output was not archived. No specific speedup over vLLM defaults, or any
benefit on a different setup, is therefore claimed.

A different GPU, model, TP size, image digest, or vLLM, ROCm, AITER, or Triton
version is outside the validated scope and requires fresh measurement and
validation. Use at your own risk and without warranty.
