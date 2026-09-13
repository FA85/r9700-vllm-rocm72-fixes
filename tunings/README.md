# Published setup-specific tuning archive

`r9700-vllm-v029-qwen38-fp8-tp2.tar.gz` contains the five published vLLM
0.29.0 FP8 W8A8 GEMM configuration files, metadata, checksums, the two small
verification/build helpers, the v0.29.0 tuning guide, license, and a copy of
the strict setup disclaimer.

Read [SETUP_SCOPE.md](SETUP_SCOPE.md) before using it. The archive is tied to
the exact dual-R9700, Qwen3.8-27B-FP8, TP=2, ROCm 7.2.x, and pinned vLLM 0.29.0
image combination documented there. It is not advertised as useful for other
hardware or software combinations.

The repository-level one-command builder consumes this archive by default:

```bash
sudo bash scripts/build-with-tunings.sh
```

The SHA-256 of the archive is recorded in `SHA256SUMS` next to it.

Archive source: `FA85/r9700-vllm-tuning`, branch
`codex/v0.29.0-tuning`, commit
`a964f2b4f9c0e43879002f700f6da0c7b76c3671`.
