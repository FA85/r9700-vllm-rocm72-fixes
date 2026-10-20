# Minimale R9700-Fixes für vLLM 0.29.0 / ROCm 7.2

[English README](README.md)

> Jedes Byte des eigenständigen Projektcodes in diesem Repository wurde von
> OpenAI Codex im Auftrag und in Zusammenarbeit mit FA85 geschrieben. Das
> Projekt entstand, weil die Performance des Standardimages unbefriedigend und
> der Stromverbrauch durch die Leerlauf-CPU-Last — ganz praktisch — einfach zu
> teuer war. Der vollständige
> [Urheberschafts- und Motivationshinweis](DISCLAIMER.md) erläutert die
> Abgrenzung zu Upstream-Code.

> **Bekannter Zielkonflikt:** Der Null-Event-Backoff senkt die CPU-Last des
> problematischen Wait-Pfads, verursachte auf dem dokumentierten Setup aber
> eine reproduzierbare Decode-Regression von etwa 55–58 auf 41–44 tok/s bei
> längeren Antworten. Dieses Repository bietet bewusst kein separates
> Ersatz-Image ohne den Backoff an. Siehe
> [Messwerte und Einordnung](KNOWN_PERFORMANCE_TRADEOFF.md).

> **Upgrade-Entscheidung (12.10.2026):** Dieses Projekt überspringt vLLM
> 0.30.0 und 0.31.0 bewusst und wartet mit der nächsten Bewertung auf v0.32.0.
> Der stabil laufende v0.29.0-Produktionsstand wird nicht durch ein Release
> ersetzt, das weder alle lokalen ROCr-Workarounds überflüssig macht noch einen
> reproduzierbaren Vorteil für genau dieses Dual-R9700-Setup mit dichtem
> Qwen3.8-FP8-Modell belegt. Das zuletzt aus diesem Repository
> veröffentlichte Release läuft beim Autor seit seiner Veröffentlichung
> durchgehend stabil und ohne beobachtete Fehler. Aktuelle Nightlies enthalten
> relevante GDN-/MTP-Korrektheitsfixes und ein optionales segmentiertes
> RDNA4-Attention-Backend. Ein erster isolierter Dual-R9700-Test zeigt nun,
> dass das nackte Nightly startet und Segmented Attention ein messbarer
> Performancekandidat ist; eine Validierung der Produktionsstabilität ist das
> noch nicht. v0.32.0 bleibt deshalb ein Prüfpunkt für isolierte Tests und
> keine automatische Upgrade-Zusage.
> **Ergänzung vom 16.10.2026:** Eine vorläufige Quellprüfung deutet darauf hin,
> dass alle drei
> bisherigen Patches zunächst entfallen könnten; nur der noch offene
> `rocprofiler-sdk`-Signal-Pool-Fix bleibt ein bedingter Kandidat, falls das
> nackte 0.32-Image die KFD-Event-Erschöpfung tatsächlich reproduziert. Siehe
> [Entscheidung zu v0.30/v0.31 und Beobachtungsliste für v0.32](UPGRADE_WATCH.de.md).

> **Ergänzung vom 20.10.2026 — kein Nachfolgeimage geplant:** Das getestete
> nackte Nightly enthält inzwischen den offiziellen RDNA-LDS-Guard für Unified
> Attention einschließlich `gfx1201`; der lokale AITER-0.1.19-Backport ist
> damit nicht mehr erforderlich. Auf diesem Dual-R9700-System verhinderte
> außerdem `HSA_TOOLS_DISABLE_REGISTER=1` beim ansonsten unveränderten Image
> die dauerhafte Leerlauf-CPU-Last, die Anlass für beide lokalen ROCr-Backoffs
> war. Die begleitenden Durchsatz- und Replay-Prüfungen zeigten keinen diesem
> Parameter zuzuordnenden Leistungsverlust. Der Parameter deaktiviert die
> Registrierung von HSA-Tools beziehungsweise Profilern und muss für
> Profiling-Sitzungen entfernt werden; er ist ein setupspezifischer operativer
> Workaround und kein Upstream-Runtime-Fix. Da diese beiden Änderungen alle
> drei lokalen Quellpatches für das getestete Nightly überflüssig machen, wird
> dieses Repository für diese Linie **kein neues gepatchtes Image
> veröffentlichen**. Das vorhandene v0.29.0-Release bleibt als historische,
> versionsgebundene Lösung verfügbar. Siehe die
> [aktualisierte Upgrade-Notiz](UPGRADE_WATCH.de.md).

## Vorläufiges Ergebnis des nackten Nightlies (16.10.2026)

Das unveränderte offizielle Image
`vllm/vllm-openai-rocm:nightly-49cb2bbf71cfd36ee5aa33d1e184b1cddff55294`
startet und bedient `Qwen/Qwen3.8-27B-FP8` auf zwei R9700 mit TP=2, MTP=2,
131.072 Tokens maximaler Modelllänge und der bisherigen festen
KV-Cache-Zuweisung von 5.000.000.000 Byte. In diesen Läufen waren weder lokale
Patches noch die veröffentlichten GEMM-Tuningdateien enthalten.

Ein lokaler Vergleich mit 25 Requests ergab folgende Mediane. Decode und
aggregierter Durchsatz sind Tokens/s, TTFT ist in Sekunden angegeben.

| Fall | Messwert | AITER Unified | Segmented statisch | Segmented getunt |
| --- | --- | ---: | ---: | ---: |
| Einzelrequest | Decode | 48,57 | 50,04 | 50,07 |
| Einzelrequest | TTFT | 0,078 | 0,122 | 0,130 |
| Langkontext, kalt | Decode | 50,16 | 52,24 | 52,28 |
| Langkontext, kalt | TTFT | 8,485 | 12,458 | 12,755 |
| Langkontext, warm | Decode | 50,21 | 52,21 | 52,35 |
| Langkontext, warm | TTFT | 0,673 | 0,345 | 0,336 |
| Parallele Requests | Aggregiert | 110,93 | 149,78 | 152,64 |
| Parallele Requests | TTFT | 2,673 | 1,393 | 1,332 |

Gegenüber AITER Unified lieferte das getunte `ROCM_SEGMENTED_ATTN` etwa 3,1 %
mehr Einzelrequest-Decode, 4,2-4,3 % mehr Langkontext-Decode und 37,6 % mehr
aggregierten Durchsatz bei parallelen Requests. Kalte Langkontext-TTFT und
Einzelrequest-TTFT wurden schlechter, warme Langkontext-TTFT und parallele
TTFT besser. Das Autotuning brachte gegenüber statischem Segmented Attention
in diesem Lauf nur 0,1-1,9 % zusätzlichen Durchsatz; hinzu kamen kleine
TTFT-Verschiebungen.

Das ist ein vorläufiges Laborergebnis und keine Releasefreigabe. Bei allen 25
AITER-gegen-getunt-Antworten unterschieden sich die Output-Hashes. Andere
Kernel können durch Rundungsunterschiede andere Samplingpfade erzeugen; vor
einer Korrektheitsaussage müssen die Inhalte trotzdem geprüft werden. Das
nackte Nightly zeigte nach der Initialisierung außerdem wieder ungefähr 200 %
Leerlauf-CPU. Damit ist das Symptom in dieser Konfiguration weiterhin
vorhanden; eine KFD-Event-Erschöpfung oder deren Ursache ist dadurch allein
nicht bewiesen. DFlash2 war nicht Teil dieser Messungen und wird getrennt
untersucht.

Dieses Repository baut ein inoffizielles Derivat des offiziellen vLLM-ROCm-
Images für die AMD Radeon AI PRO R9700 (`gfx1201`). Es enthält genau drei
gezielte Änderungen:

1. **AITER-LDS-Guard** — ein minimaler Backport für `amd-aiter 0.1.19`,
   abgeleitet aus [ROCm/aiter#5035](https://github.com/ROCm/aiter/pull/5035).
2. **ROCr-AsyncEventsLoop-Backoff** — ein Backport aus
   [ROCm/rocm-systems#7898](https://github.com/ROCm/rocm-systems/pull/7898),
   upstream zusammengeführt als
   [`46558b7`](https://github.com/ROCm/rocm-systems/commit/46558b7af4dc79b8b8014619c1afdb82db079a9f).
   Die spätere Korrektur für gemischte Signal-Batches unter nativem Linux ist
   Upstream-Commit
   [`867d8de`](https://github.com/ROCm/rocm-systems/commit/867d8def53f68bbb892b4fd5605eff727eab6c0f)
   aus [ROCm/rocm-systems#13149](https://github.com/ROCm/rocm-systems/pull/13149).
3. **ROCr-Null-Event-Backoff** — ein eng begrenzter Workaround für blockierende
   `InterruptSignal`-Waits ohne KFD-Event. Statt
   `hsaKmtWaitOnEvent_Ext(nullptr, ...)` in einer engen Schleife aufzurufen,
   wird das Userspace-Signal mit 20 bis 200 Mikrosekunden Backoff abgefragt.
   Dieser Workaround reduziert die beobachtete Leerlauf-CPU-Last, ist aber mit
   einer [dokumentierten Decode-Regression](KNOWN_PERFORMANCE_TRADEOFF.md)
   verbunden.

Nicht enthalten sind modellspezifisches GEMM-Tuning, HIP-`LD_PRELOAD`-Hook,
Hybrid-/True-Blocking-Experimente, Debug-Symbole oder eine `SYS_PTRACE`-
Anforderung.

Das modellspezifische Tuning bleibt im separaten Repository
[`r9700-vllm-tuning`](https://github.com/FA85/r9700-vllm-tuning). Wie daraus
zusammen mit diesen drei Fixes ein einziges lokales Image gebaut wird, steht in
der [Bauanleitung mit v0.29.0-Tuning](BUILD_WITH_TUNINGS.de.md). Der Kurzweg
nach dem Klonen dieses Repositorys verwendet das mitgelieferte,
[streng setupgebundene Archiv](tunings/SETUP_SCOPE.md):

```bash
sudo bash scripts/build-with-tunings.sh
```

## Hinweise, die zur Diagnose führten

Die Lösung entstand nicht im luftleeren Raum. Der
[AITER-LDS-PR #5035](https://github.com/ROCm/aiter/pull/5035) lokalisierte den
gfx1201-Startfehler auf eine 3D-Unified-Attention-Konfiguration oberhalb des
64-KiB-LDS-Limits und lieferte die Grundlage für den hier auf `amd-aiter
0.1.19` zurückportierten Guard.

Beim Leerlaufproblem wies der bereits unabhängig veröffentlichte
[ROCm-Systems-Issue #7860](https://github.com/ROCm/rocm-systems/issues/7860)
auf dieselbe heiße Stelle in HSA/ROCr hin: `Runtime::AsyncEventsLoop`. Das war
ein wichtiger Wegweiser für unsere Profiler- und Debuggeranalyse. Der
AsyncEventsLoop-Patch selbst folgt dem später zusammengeführten
[ROCm-Systems-PR #7898](https://github.com/ROCm/rocm-systems/pull/7898) und
dessen offiziellem Merge-Commit
[`46558b7`](https://github.com/ROCm/rocm-systems/commit/46558b7af4dc79b8b8014619c1afdb82db079a9f).
Der Upstream-Folgecommit für gemischte Signal-Batches auf interruptfähigem
nativem Linux ist
[`867d8de`](https://github.com/ROCm/rocm-systems/commit/867d8def53f68bbb892b4fd5605eff727eab6c0f).
Issue #7860 beschreibt jedoch einen anderen Auslöser; er belegt deshalb nicht,
dass dessen konkrete Ursache mit unserem vLLM-Fall identisch war. Der
zusätzliche Null-Event-Pfad wurde in unserem Setup separat bis
`InterruptSignal::WaitRelaxed` und einem ungültigen KFD-Event-Handle
zurückverfolgt und bleibt ein lokaler Workaround. Für diesen zusätzlichen
Null-Event-Patch gibt es keinen entsprechenden Upstream-Commit im offiziellen
ROCm-Repository; einen der beiden AsyncEventsLoop-Commits als seine Quelle
auszugeben wäre sachlich falsch.

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
Fix. Auf diesem Setup senkte er zugleich den Decode-Durchsatz längerer Antworten
reproduzierbar um ungefähr 20 bis 29 Prozent. Diese Abwägung ist in
[KNOWN_PERFORMANCE_TRADEOFF.md](KNOWN_PERFORMANCE_TRADEOFF.md) vollständig
dokumentiert.

Quellen und Lizenzhinweise stehen in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
