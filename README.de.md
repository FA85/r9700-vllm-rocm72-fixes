# vLLM Nightly da913 / ROCm 10 auf zwei R9700

[English README](README.md)

Dieses Repository dokumentiert inzwischen zwei Generationen unseres
Dual-R9700-Setups:

- das historische, lokal gepatchte vLLM-0.29.0-/ROCm-7.2-Image;
- den heute verwendeten, exakt gepinnten Stock-Nightly-Build auf ROCm 10.0,
  der ohne lokale Quellpatches läuft.

> Jedes Byte des eigenständigen Projektcodes in diesem Repository wurde von
> OpenAI Codex im Auftrag und in Zusammenarbeit mit FA85 geschrieben. Das
> Projekt entstand, weil die Performance des damaligen Standardimages
> unbefriedigend und die Stromrechnung wegen der Leerlauf-CPU-Last schlicht zu
> hoch war. Siehe den vollständigen [Disclaimer](DISCLAIMER.md).

## Aktueller Betriebsstand

Wir verwenden nicht einfach das jeweils neueste Nightly und wechseln auch
nicht stillschweigend auf vLLM 0.32.0. Der dokumentierte und getestete Stand
ist exakt:

```text
Tag:    nightly-rocm100-da9134bc89364465f68aa679564435936d157a14
Digest: sha256:56d1a901c86f9ca12c98e5efb00467eaebc299378428394ec3afcb45d4635fc3
```

| Bestandteil | Verwendete Konfiguration |
| --- | --- |
| Basisimage | offizielles, unverändertes vLLM-ROCm-Nightly am obigen Digest |
| ROCm | 10.0 |
| GPUs | 2 × AMD Radeon AI PRO R9700 (`gfx1201`) |
| Modell | `Qwen/Qwen3.8-27B-FP8` |
| Parallelität | Tensor Parallelism 2 |
| Attention | `ROCM_SEGMENTED_ATTN` |
| Speculative Decoding | MTP mit zwei spekulativen Tokens |
| Modelllänge | 131.072 Tokens |
| lokale Quellpatches | keine |
| Idle-CPU-Workaround | `HSA_TOOLS_DISABLE_REGISTER=1` |
| alte v0.29-Tuning-JSONs | nicht enthalten |

[vLLM 0.32.0](https://github.com/vllm-project/vllm/releases/tag/v0.32.0)
ist inzwischen erschienen, aber jünger als dieser getestete Pin. Der
Release-Tag ersetzt den hier dokumentierten Digest deshalb nicht ohne einen
eigenen Reproduktions- und Stabilitätstest.

## Warum kein neues Patch-Image erscheint

Bei der Unterstützung und praktischen Stabilität von `gfx1201` hat sich in
wenigen Wochen sichtbar viel getan:

- der früher lokal benötigte
  [AITER-LDS-Guard](https://github.com/ROCm/aiter/pull/4868) ist upstream
  verfügbar;
- vLLM besitzt mit
  [`ROCM_SEGMENTED_ATTN`](https://github.com/vllm-project/vllm/pull/59132)
  ein eigenes optionales RDNA3-/RDNA4-Backend;
- mehrere für Qwen3.8, GDN, Prefix Cache und MTP relevante Korrekturen sind
  upstream angekommen;
- der oben gepinnte Stock-Build startet und arbeitet auf 2× R9700 ohne die
  drei früheren lokalen Quellpatches;
- `HSA_TOOLS_DISABLE_REGISTER=1` verhindert auf dem dokumentierten System die
  zuvor beobachtete dauerhafte Leerlauf-CPU-Last, ohne dass wir in den
  begleitenden Replay- und Durchsatzmessungen einen Leistungsverlust durch
  diesen Parameter feststellen konnten.

Der Parameter deaktiviert die Registrierung von HSA-Tools beziehungsweise
Profilern. Für `rocprof`, ROCProfiler oder vergleichbare Werkzeuge muss er
entfernt werden. Er ist ein setupspezifischer Betriebs-Workaround und kein
Beweis dafür, dass der zugrunde liegende ROCr-Pfad allgemein repariert ist.

Da der AITER-Fix upstream vorliegt und die beiden ROCr-Backoffs für unseren
normalen Betrieb nicht mehr benötigt werden, veröffentlichen wir für diesen
Nightly-Stand kein neues gepatchtes Image. Das bisherige v0.29.0-Release
bleibt als historische, fest gepinnte Lösung erhalten und läuft beim Autor
seit seiner Veröffentlichung durchgehend stabil und ohne beobachtete Fehler.

## Vom Host zum laufenden Container

Die folgenden Schritte verwenden den oben genannten Digest, einen
rootless-Podman-Store des Benutzers `vllm`, zwei R9700 und eigene
Nightly-/ROCm-10-Compiler-Caches. Der Hugging-Face-Modellcache darf gemeinsam
mit dem alten Setup verwendet werden.

### 1. Verzeichnisse anlegen

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

Die vLLM-, Triton- und TorchInductor-Caches werden nicht mit v0.29, ROCm 7.2
oder einem anderen Nightly geteilt.

### 2. Exakt gepinntes Stock-Image laden

```bash
VLLM_UID="$(id -u vllm)"

sudo -u vllm -H env XDG_RUNTIME_DIR="/run/user/$VLLM_UID" \
  podman pull \
  docker.io/vllm/vllm-openai-rocm@sha256:56d1a901c86f9ca12c98e5efb00467eaebc299378428394ec3afcb45d4635fc3
```

Optional den tatsächlich geladenen Digest kontrollieren:

```bash
sudo -u vllm -H env XDG_RUNTIME_DIR="/run/user/$VLLM_UID" \
  podman image inspect \
  docker.io/vllm/vllm-openai-rocm@sha256:56d1a901c86f9ca12c98e5efb00467eaebc299378428394ec3afcb45d4635fc3 \
  --format '{{index .RepoDigests 0}}'
```

### 3. Container mit den verwendeten Parametern starten

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

Der erste Start kann wegen JIT-/Triton-Kompilierung deutlich länger dauern.
Die feste KV-Zuweisung von 5.000.000.000 Byte und
`--gpu-memory-utilization 0.72` lassen auf unserem Host noch Raum für den
separaten 4B-Modellserver. Diese Werte sind kein allgemeines Optimum.

Der aktuelle Standard verwendet die statische Segmented-Attention-
Konfiguration. Das separat getestete Autotuning wird mit

```text
--kernel-config.enable_rocm_segmented_attn_autotune=True
```

aktiviert, gehört aber bewusst nicht zum obigen Standardbefehl.

### 4. Start verfolgen und API prüfen

Die Containerlogs liegen bei diesem Setup im Journal:

```bash
sudo journalctl -t qwen38-nightly-da913-rocm100-stock -a -f -o cat
```

Nach `Uvicorn running`:

```bash
curl -fsS http://127.0.0.1:8001/v1/models

curl -fsS http://127.0.0.1:8001/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "Qwen/Qwen3.8-27B-FP8",
    "messages": [{"role": "user", "content": "Antworte nur mit: OK"}],
    "temperature": 0,
    "max_tokens": 16
  }'
```

Die Leerlauf-CPU nach mindestens fünf Minuten ohne Requests kontrollieren:

```bash
VLLM_UID="$(id -u vllm)"

sudo -u vllm -H env XDG_RUNTIME_DIR="/run/user/$VLLM_UID" \
  podman top qwen38-nightly-da913-rocm100-stock hpid,pcpu,state,comm
```

### 5. Stoppen, entfernen und neu starten

```bash
VLLM_UID="$(id -u vllm)"

sudo -u vllm -H env XDG_RUNTIME_DIR="/run/user/$VLLM_UID" \
  podman stop -t 30 qwen38-nightly-da913-rocm100-stock

sudo -u vllm -H env XDG_RUNTIME_DIR="/run/user/$VLLM_UID" \
  podman rm qwen38-nightly-da913-rocm100-stock
```

Danach Schritt 3 wiederholen. Modell-, Compiler- und Image-Caches bleiben
erhalten.

## Gemessene Backend-Ergebnisse

In einem früheren lokalen 25-Request-Vergleich auf zwei R9700 lieferte
`ROCM_SEGMENTED_ATTN` gegenüber `ROCM_AITER_UNIFIED_ATTN` etwa 3–4 % mehr
Einzel- und Langkontext-Decode sowie 35–38 % mehr aggregierten Durchsatz bei
vier parallelen Requests. Segmented-Attention-Autotuning brachte gegenüber
der statischen Variante nur weitere 0,1–1,9 %. TTFT verschob sich je nach Fall
in beide Richtungen. Das sind setupspezifische Messwerte, keine allgemeinen
R9700-Garantien.

DFlash2 wurde explorativ getestet, gehört wegen seines zusätzlichen
Speicherbedarfs aber nicht zum aktuellen Betriebsprofil. Wir bleiben bei
MTP=2.

## Tunings

Die fünf veröffentlichten FP8-GEMM-Tuningdateien wurden für vLLM 0.29.0,
ROCm 7.2 und den damaligen AITER-/Triton-Stand vermessen. Sie werden nicht in
den ROCm-10-Nightly kopiert. Ein Nightly-Tuning muss gegen exakt den oben
genannten Image-Digest neu gemessen, gebaut und mit identischen Requests gegen
Stock verglichen werden. Alte JSONs nur deshalb weiterzuverwenden, weil Modell
und GPU gleich heißen, wäre methodisch falsch.

## Historischer v0.29.0-Patchstand

Das ursprüngliche Image enthielt:

1. den AITER-LDS-Backport für `gfx1201`;
2. den ROCr-AsyncEventsLoop-Backoff;
3. den lokalen ROCr-Null-Event-Backoff.

Die offiziellen ROCr-Commits, auf die sich der historische
AsyncEventsLoop-Backport bezieht, sind
[`46558b7`](https://github.com/ROCm/rocm-systems/commit/46558b7af4dc79b8b8014619c1afdb82db079a9f)
und der Linux-Folgefix
[`867d8de`](https://github.com/ROCm/rocm-systems/commit/867d8def53f68bbb892b4fd5605eff727eab6c0f).
Für den zusätzlichen lokalen Null-Event-Backoff gibt es keinen entsprechenden
Upstream-Commit. Sein reproduzierbarer Decode-Nachteil ist in
[KNOWN_PERFORMANCE_TRADEOFF.md](KNOWN_PERFORMANCE_TRADEOFF.md) dokumentiert.

Die alten Artefakte bleiben absichtlich erhalten:

- [v0.29.0-Bauanleitung mit Tunings](BUILD_WITH_TUNINGS.de.md)
- [Upgrade- und Quellenchronik](UPGRADE_WATCH.de.md)
- [Drittanbieter- und Lizenzhinweise](THIRD_PARTY_NOTICES.md)

`Containerfile`, `patches/` und die bisherigen Buildskripte gelten nur für den
historischen, fest gepinnten v0.29.0-Stand. Sie sind keine Patches für den
aktuellen Nightly-Pin.

## Reichweite

Dies ist ein unabhängiger Erfahrungs- und Reproduktionsbericht, kein
offizielles AMD-, ROCm-, AITER-, Qwen- oder vLLM-Paket. Die Parameter wurden
auf genau zwei R9700 mit dem genannten Modell und TP=2 ermittelt. Andere
Treiber, Firmwarestände, Modelle, Quantisierungen, GPU-Anordnungen oder
Parallelitätsgrade können andere Ergebnisse liefern.
