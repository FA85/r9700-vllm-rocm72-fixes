# Minimale R9700-Fixes für vLLM 0.29.0 / ROCm 7.2

[English README](README.md)

> Jedes Byte des eigenständigen Projektcodes in diesem Repository wurde von
> OpenAI Codex im Auftrag und in Zusammenarbeit mit FA85 geschrieben. Das
> Projekt entstand, weil die Performance des Standardimages unbefriedigend und
> der Stromverbrauch durch die Leerlauf-CPU-Last — ganz praktisch — einfach zu
> teuer war. Der vollständige
> [Urheberschafts- und Motivationshinweis](DISCLAIMER.md) erläutert die
> Abgrenzung zu Upstream-Code.

Dieses Repository baut ein inoffizielles Derivat des offiziellen vLLM-ROCm-
Images für die AMD Radeon AI PRO R9700 (`gfx1201`). Es enthält genau drei
gezielte Änderungen:

1. **AITER-LDS-Guard** — ein minimaler Backport für `amd-aiter 0.1.19`,
   abgeleitet aus [ROCm/aiter#5035](https://github.com/ROCm/aiter/pull/5035).
2. **ROCr-AsyncEventsLoop-Backoff** — ein Backport aus
   [ROCm/rocm-systems#7898](https://github.com/ROCm/rocm-systems/pull/7898).
3. **ROCr-Null-Event-Backoff** — ein eng begrenzter Workaround für blockierende
   `InterruptSignal`-Waits ohne KFD-Event. Statt
   `hsaKmtWaitOnEvent_Ext(nullptr, ...)` in einer engen Schleife aufzurufen,
   wird das Userspace-Signal mit 20 bis 200 Mikrosekunden Backoff abgefragt.

Nicht enthalten sind modellspezifisches GEMM-Tuning, HIP-`LD_PRELOAD`-Hook,
Hybrid-/True-Blocking-Experimente, Debug-Symbole oder eine `SYS_PTRACE`-
Anforderung.

## Gültiger Versionsbereich

Der Build ist fest auf folgende Kombination begrenzt:

- `vllm/vllm-openai-rocm:v0.29.0` mit Digest
  `sha256:e5e47f6aaab675c252c381f0dac237b31b10d87bb74d092b07fb4065efd7f5a1`
- ROCm 7.2.3 / ROCr `libhsa-runtime64.so.1.18.0`
- ursprüngliche ROCr-SHA-256
  `bec3c44c469d79c79c70bded96ac1c88d1c5c5e0e4b7abfa26096029075090f7`
- ROCr-Quellcommit `c7e40e16bca10311af72aee09cfa0cd1726f70a7`
- `amd-aiter 0.1.19` aus dem festgelegten Basisimage

Bei einer Abweichung bricht der Build ab. Für eine neue Upstream-Version müssen
die Patches neu abgeglichen und getestet werden; die Sicherheitsprüfungen
sollten nicht einfach entfernt werden.

## Bauen und prüfen

Benötigt werden Linux x86-64, Bash, Git und Podman. Mit
`CONTAINER_TOOL=docker` kann Docker verwendet werden. Zum Bauen ist keine GPU
nötig, der Laufzeittest muss aber auf dem R9700-System stattfinden.

```bash
git clone https://github.com/FA85/r9700-vllm-rocm72-fixes.git
cd r9700-vllm-rocm72-fixes
bash scripts/build.sh
GPU_TEST=1 bash scripts/verify.sh
```

Das Standardergebnis heißt
`localhost/r9700-vllm:v0.29.0-rocm72-minimal-fixes`. Ein anderer Name kann mit
`IMAGE=...` gesetzt werden. Die statische Prüfung kontrolliert die drei Fixes,
die ersetzte ROCr-Bibliothek und die Abwesenheit der verworfenen Experimente.
Der GPU-Smoke-Test ersetzt noch keinen vollständigen vLLM-Last- und
Latenzvergleich.

## Startbeispiel

```bash
HF_CACHE=/var/lib/vllm/huggingface \
  bash scripts/run-example.sh \
  --port 8001 \
  --max-model-len 131072 \
  --max-num-seqs 4
```

Voreingestellt sind `Qwen/Qwen3.8-27B-FP8`, zwei GPUs, Tensor Parallelism 2 und
`NCCL_PROTO=Simple`. `MODEL`, `HIP_VISIBLE_DEVICES`,
`TENSOR_PARALLEL_SIZE` und `NCCL_PROTO` können als Umgebungsvariablen
überschrieben werden.

## GHCR-Veröffentlichung

Der Workflow `.github/workflows/publish.yml` baut bei einem `v*`-Tag oder bei
manuellem Start und veröffentlicht nach
`ghcr.io/fa85/r9700-vllm-rocm72-fixes:<tag>`. Wegen der Imagegröße verwendet er
einen selbst gehosteten Linux-x86-64-Runner mit Podman; eine GPU ist nur für die
nachgelagerte Laufzeitprüfung erforderlich.

```bash
git tag v0.1.0
git push origin v0.1.0
```

Nach dem ersten Push muss das Package gegebenenfalls in GitHub Packages auf
„public“ gestellt werden. Das veröffentlichte Tag sollte auf dem R9700-Host mit
`GPU_TEST=1 IMAGE=ghcr.io/... bash scripts/verify.sh` geprüft werden.

## Einordnung

Die drei Änderungen wurden durch CPU-Profiling und Debugger-Probes auf einem
System mit zwei R9700 eingegrenzt und beseitigten dort den AITER-LDS-Fehler und
das beobachtete CPU-Spinning im Leerlauf. Das Image bleibt ein inoffizieller
Kompatibilitäts-Build. Insbesondere der Null-Event-Backoff ist ein lokal
diagnostizierter Workaround und noch kein allgemein bestätigter ROCr-Upstream-
Fix.

Quellen und Lizenzhinweise stehen in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
