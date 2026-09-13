# Kombiniertes Image mit Fixes und v0.29.0-Tuning bauen

[English version](BUILD_WITH_TUNINGS.md)

Diese Anleitung baut ein lokales Image mit:

- den fünf veröffentlichten FP8-W8A8-GEMM-Tuningdateien für
  `Qwen/Qwen3.8-27B-FP8` auf zwei AMD Radeon AI PRO R9700;
- dem AITER-LDS-Fix;
- dem ROCr-AsyncEventsLoop-Backoff;
- dem ROCr-Null-Event-Backoff.

Die Reihenfolge ist wichtig: Zuerst wird das Tuning auf das unveränderte,
digestgebundene vLLM-Image gelegt. Danach werden die drei allgemeinen Fixes auf
dieses lokale Tuning-Image gebaut.

## Schnellstart

Nach dem Klonen dieses Repositorys genügt auf dem R9700-Host:

```bash
sudo bash scripts/build-with-tunings.sh
```

Das Skript wechselt automatisch zum Benutzer `vllm`, lädt den veröffentlichten
Tuning-Branch in ein temporäres Verzeichnis, prüft dessen fünf Dateien, baut
beide Image-Schichten und führt die statische Abschlussprüfung aus. Mit

```bash
sudo env GPU_TEST=1 bash scripts/build-with-tunings.sh
```

wird zusätzlich der HIP-Smoke-Test auf den R9700 ausgeführt. Das fertige Image
heißt `localhost/vllm-r9700:qwen38-v0.29.0-tuned-fixes`.

Solange das Tuning-Repository nicht öffentlich erreichbar ist, kann eine
SSH-URL oder ein vorhandener Checkout angegeben werden:

```bash
sudo env TUNING_REPO=git@github.com:FA85/r9700-vllm-tuning.git \
  bash scripts/build-with-tunings.sh

sudo env TUNING_DIR=/var/lib/vllm/r9700-vllm-tuning \
  bash scripts/build-with-tunings.sh
```

Die folgenden Abschnitte dokumentieren denselben Ablauf Schritt für Schritt.

## Voraussetzungen

- Linux x86-64 mit Bash, Git, Python 3 und Podman
- ausreichend freier Speicher für das vLLM-Basisimage und den ROCr-Build
- Benutzer `vllm` mit funktionierendem Rootless-Podman
- Zugriff auf
  [`FA85/r9700-vllm-tuning`](https://github.com/FA85/r9700-vllm-tuning)
- für die Laufzeitprüfung: zwei R9700, `/dev/kfd` und `/dev/dri`

Alle Podman-Befehle müssen unter demselben Benutzer laufen. Die folgenden
Befehle verwenden deshalb durchgehend `sudo -u vllm -H`.

## 1. Beide Repositories auschecken

```bash
sudo install -d -o vllm -g vllm /var/lib/vllm

sudo -u vllm -H git clone \
  --branch codex/v0.29.0-tuning \
  git@github.com:FA85/r9700-vllm-tuning.git \
  /var/lib/vllm/r9700-vllm-tuning

sudo -u vllm -H git clone \
  https://github.com/FA85/r9700-vllm-rocm72-fixes.git \
  /var/lib/vllm/r9700-vllm-rocm72-fixes
```

Bei bereits vorhandenen Checkouts stattdessen aktualisieren:

```bash
sudo -u vllm -H git -C /var/lib/vllm/r9700-vllm-tuning pull --ff-only
sudo -u vllm -H git -C /var/lib/vllm/r9700-vllm-rocm72-fixes pull --ff-only
```

## 2. Veröffentlichte Tuningdateien prüfen

```bash
sudo -u vllm -H python3 \
  /var/lib/vllm/r9700-vllm-tuning/r9700-tuning/scripts/verify_published_configs.py
```

Die Prüfung muss fünf Dateien und insgesamt 90 M-Profile bestätigen. Sie prüft
Struktur und SHA-256-Werte, führt aber keinen neuen Benchmark aus.

## 3. Tuning-Image bauen

```bash
sudo -u vllm -H bash \
  /var/lib/vllm/r9700-vllm-tuning/r9700-tuning/scripts/build_tuned_vllm_image.sh \
  --root /var/lib/vllm/r9700-vllm-tuning/r9700-tuning \
  --image docker.io/vllm/vllm-openai-rocm@sha256:e5e47f6aaab675c252c381f0dac237b31b10d87bb74d092b07fb4065efd7f5a1 \
  --model Qwen/Qwen3.8-27B-FP8 \
  --tp-size 2 \
  --tag localhost/vllm-r9700:qwen38-v0.29.0-tuned
```

Dieser Weg verwendet den bereits veröffentlichten Tuning-Satz. Ein erneuter
mehrstündiger Tuning-Lauf ist zum Nachbauen des Images nicht erforderlich.

## 4. Die drei Fixes darauf bauen

```bash
sudo -u vllm -H env \
  BASE_IMAGE=localhost/vllm-r9700:qwen38-v0.29.0-tuned \
  IMAGE=localhost/vllm-r9700:qwen38-v0.29.0-tuned-fixes \
  bash /var/lib/vllm/r9700-vllm-rocm72-fixes/scripts/build.sh
```

Das Buildskript erkennt das lokale Tuning-Image und versucht deshalb nicht,
es aus einer Registry zu laden. Es baut ROCr, übernimmt nur die gepatchte
Bibliothek in das finale Image und führt anschließend die statische Prüfung
der drei Fixes aus.

## 5. Kombiniertes Image prüfen

```bash
sudo -u vllm -H env \
  IMAGE=localhost/vllm-r9700:qwen38-v0.29.0-tuned-fixes \
  GPU_TEST=1 \
  bash /var/lib/vllm/r9700-vllm-rocm72-fixes/scripts/verify.sh

sudo -u vllm -H podman run --rm --pull=never \
  --entrypoint python3 \
  localhost/vllm-r9700:qwen38-v0.29.0-tuned-fixes \
  -c 'import importlib.util; from pathlib import Path; root=Path(importlib.util.find_spec("vllm").origin).resolve().parent; print(Path("/opt/r9700-tuning/metadata.json").read_text()); print(*sorted((root / "model_executor/layers/quantization/utils/configs").glob("*AMD_Radeon_R9700*")), sep="\n")'
```

Der erste Befehl muss die drei Fixes und den HIP-Smoke-Test als `PASS`
melden. Der zweite zeigt die eingebetteten Tuning-Metadaten und fünf
R9700-Konfigurationsdateien.

## 6. vLLM starten

Zuerst dauerhafte Cache-Verzeichnisse anlegen:

```bash
sudo install -d -o vllm -g vllm \
  /var/lib/vllm/huggingface \
  /var/lib/vllm/vllm-0.29.0-cache/vllm \
  /var/lib/vllm/vllm-0.29.0-cache/triton \
  /var/lib/vllm/vllm-0.29.0-cache/torchinductor
```

Dann den Server starten:

```bash
sudo -u vllm -H env XDG_RUNTIME_DIR=/run/user/987 \
  podman run -d --pull=never \
  --name qwen38-0.29.0-tuned-fixes \
  --network host --ipc host \
  --device /dev/kfd --device /dev/dri \
  --group-add keep-groups \
  --security-opt seccomp=unconfined \
  -v /var/lib/vllm/huggingface:/root/.cache/huggingface \
  -v /var/lib/vllm/vllm-0.29.0-cache/vllm:/root/.cache/vllm \
  -v /var/lib/vllm/vllm-0.29.0-cache/triton:/root/.triton \
  -v /var/lib/vllm/vllm-0.29.0-cache/torchinductor:/root/.cache/torchinductor \
  -e TRITON_CACHE_DIR=/root/.triton \
  -e TORCHINDUCTOR_CACHE_DIR=/root/.cache/torchinductor \
  -e HIP_VISIBLE_DEVICES=0,1 \
  -e PYTHONUNBUFFERED=1 \
  -e NCCL_PROTO=Simple \
  -e VLLM_EXECUTE_MODEL_TIMEOUT_SECONDS=1800 \
  localhost/vllm-r9700:qwen38-v0.29.0-tuned-fixes \
  Qwen/Qwen3.8-27B-FP8 \
    --port 8001 \
    --tensor-parallel-size 2 \
    --kv-cache-memory-bytes 5000000000 \
    --max-num-seqs 4 \
    --max-model-len 131072 \
    --max-num-batched-tokens 9216 \
    --gpu-memory-utilization 0.9 \
    --mamba-cache-mode none \
    --enable-auto-tool-choice \
    --tool-call-parser qwen3_coder \
    --reasoning-parser qwen3 \
    --speculative-config '{"method":"mtp","num_speculative_tokens":2}' \
    --enable-per-request-metrics \
    --enable-prompt-tokens-details \
    --per-request-spec-decode-metrics summary
```

`987` muss die tatsächliche UID des Benutzers `vllm` sein. Sie kann mit
`id -u vllm` geprüft werden. Falls sie abweicht, `XDG_RUNTIME_DIR` entsprechend
ändern.

Der Serverstatus lässt sich danach so prüfen:

```bash
curl -fsS http://127.0.0.1:8001/v1/models
sudo -u vllm -H env XDG_RUNTIME_DIR=/run/user/987 \
  podman logs --tail 100 qwen38-0.29.0-tuned-fixes
```

Der obige Start folgt dem veröffentlichten Tuning-Vertrag und lässt vLLM den
Attention-Backend auswählen. Um den gepatchten AITER-LDS-Pfad ausdrücklich zu
verwenden, zusätzlich vor dem Imagenamen

```bash
-e VLLM_ROCM_USE_AITER=1
```

und nach dem Modellnamen

```bash
--attention-backend ROCM_AITER_UNIFIED_ATTN
```

einfügen. Diesen Modus getrennt testen und mit identischen Prompts gegen den
Standard-Backend vergleichen. Auch MTP kann je nach Attention-Backend und
Lastprofil Gewinn oder Zusatzaufwand bedeuten; deshalb den AITER-Lauf einmal
mit und einmal ohne `--speculative-config` messen.

## Versionsgrenze

Tuning und Fixes gelten nur für die oben festgelegte vLLM-0.29.0-/ROCm-7.2-
Basis. Bei einem anderen Image-Digest, Modell, GPU-Typ oder einer anderen
vLLM-/AITER-/ROCr-Version müssen Kompatibilität, Tuning und Patches erneut
geprüft werden. Digest- und Prüfsummenprüfungen sollten nicht umgangen werden.
