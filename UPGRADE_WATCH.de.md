# vLLM-Upgrade-Beobachtung: v0.32.0 und das getestete Nightly nach v0.31

[English version](UPGRADE_WATCH.md)

Stand: 12.10.2026; am 16.10.2026 um den vorläufigen v0.32-Patch- und
Tuningplan und am 20.10.2026 um die getestete Patch-Ablösung ergänzt.

Diese Notiz hält eine Projektentscheidung fest und ist keine allgemeine
Empfehlung für alle ROCm-Nutzer. Das Referenzsystem besteht aus:

- zwei AMD Radeon AI PRO R9700 (`gfx1201`) mit Tensor Parallelism 2;
- `Qwen/Qwen3.8-27B-FP8`, einem dichten blockskalierten FP8-Modell;
- dem von diesem Repository festgelegten vLLM-0.29.0-/ROCm-7.2.3-Image;
- AITER Unified Attention, fünf lokal gemessenen GEMM-Tuningdateien und MTP
  mit zwei spekulativen Tokens;
- den drei in diesem Repository dokumentierten lokalen Fixes.

## Ergänzung vom 20.10.2026: kein neues gepatchtes Image

Mit dem getesteten nackten Nightly ist dieses Projekt über die drei lokalen
Quellpatches hinausgekommen:

- Seine AITER-Version enthält den offiziellen
  [RDNA-LDS-Guard für Unified Attention](https://github.com/ROCm/aiter/pull/4868)
  einschließlich `gfx1201` und ersetzt damit den lokalen AITER-0.1.19-Backport.
- `HSA_TOOLS_DISABLE_REGISTER=1` verhinderte beim ansonsten unveränderten
  Image die dauerhafte Leerlauf-CPU-Last, die Anlass für beide lokalen
  ROCr-Backoffs war.
- Die begleitenden Durchsatzmessungen und Replays historischer Requests
  zeigten auf dem Referenzsystem keinen diesem Parameter zuzuordnenden
  Leistungsverlust.

`HSA_TOOLS_DISABLE_REGISTER=1` deaktiviert die Registrierung von HSA-Tools und
Profilern. Für ROCm-/HSA-Profiling muss der Parameter entfernt werden; das
Ergebnis ist weder ein allgemeiner ROCr-Fix noch eine Garantie für andere
Anwendungen. Für den normalen Inferenzbetrieb dieses Repositorys machen der
Upstream-LDS-Guard und dieser Runtime-Parameter jedoch alle drei lokalen
Binär- beziehungsweise Quellpatches überflüssig.

Folglich wird dieses Repository für die getestete Nightly-Linie **kein neues
gepatchtes Containerimage veröffentlichen**. Das vorhandene v0.29.0-Release
bleibt als historische, versionsgebundene Lösung für den dort dokumentierten
Stack verfügbar. Eine spätere Image-Veröffentlichung würde ein neues,
reproduzierbares Problem voraussetzen, das tatsächlich wieder eine
Quelländerung benötigt; eine höhere vLLM-Versionsnummer allein genügt nicht.

## Frühere Entscheidung vor Veröffentlichung von v0.32.0

v0.31.0 ist inzwischen stabil veröffentlicht. Dieses Projekt stellt sein
Produktivimage trotzdem nicht darauf um. Der nächste Prüfpunkt ist v0.32.0.
Das ist keine Upgrade-Zusage: Auch v0.32.0 muss die setupspezifische Schranke
weiter unten in einem isolierten Image bestehen.

Für das Warten gibt es inzwischen konkretere Gründe als bloße
Versionsvorsicht:

- [vLLM #56531](https://github.com/vllm-project/vllm/pull/56531), nach dem
  v0.31.0-Release-Cut zusammengeführt, hält spekulationsfähige hybride
  Recurrent-Zeilen auch in Schritten ohne Drafts auf einem konsistenten
  Zustandspfad.
- [vLLM #55504](https://github.com/vllm-project/vllm/pull/55504), am
  10.10.2026 zusammengeführt, verhindert, dass überbreite GDN-Decode-Zeilen in
  ein begrenztes spekulatives State-Layout gelangen. Beide Änderungen sind
  direkt für hybride GDN-Modelle mit spekulativem Decoding relevant.
- [vLLM #55601](https://github.com/vllm-project/vllm/pull/55601) und
  [vLLM #60533](https://github.com/vllm-project/vllm/pull/60533) korrigieren
  State-Indizierung und Checkpoint-Grenzen des Prefix Cache bei hybriden
  Mamba-/GDN-Modellen. Die veröffentlichten Auslöser enthalten
  DFlash2-/EAGLE-Layouts; die Übertragbarkeit auf unsere exakte
  MTP-Konfiguration muss deshalb noch gezeigt werden.
- [vLLM #59132](https://github.com/vllm-project/vllm/pull/59132) ergänzt das
  optionale RDNA3-/RDNA4-Backend `ROCM_SEGMENTED_ATTN` und enthält einen
  direkten Vergleich mit zwei R9700, TP=2 und `Qwen/Qwen3.8-27B-FP8`. Damit
  ist es ein ernsthafter Laborkandidat, aber noch kein Beleg für einen Vorteil
  gegenüber unserem getunten Produktionsstack mit identischen Requests und
  Cache-Einstellungen.
- [vLLM #57560](https://github.com/vllm-project/vllm/pull/57560) ergänzt einen
  optionalen AITER-FlyDSL-Pfad für GDN-Prefill. Validiert wurde er auf MI355X
  mit einem wesentlich größeren Qwen3.8-Modell, nicht auf `gfx1201` mit diesem
  dichten 27B-Checkpoint.

Weitere offene Änderungen sind das optionale native RDNA3-/RDNA4-All-Reduce
([vLLM #57767](https://github.com/vllm-project/vllm/pull/57767)) und der Fix,
der den AITER-Unified-Attention-Schalter auf RDNA tatsächlich wirksam macht
([vLLM #56040](https://github.com/vllm-project/vllm/pull/56040)). Offene Pull
Requests sind keine Grundlage für eine Produktionsfreigabe;
entscheidend bleibt der isolierte Test eines stabilen Release-Images.

## Warum dieses Projekt v0.30.0 überspringt

Das bestehende v0.29.0-Image läuft im Produktivbetrieb stabil. Das zuletzt aus
diesem Repository veröffentlichte Release läuft beim Autor seit seiner
Veröffentlichung durchgehend stabil und ohne beobachtete Fehler. Das ist ein
Erfahrungsbericht über genau diesen Einsatz und keine allgemeine
Stabilitätsgarantie. v0.30.0 ändert den ROCm-Softwarestack erheblich, unter
anderem TheRock-Basis, PyTorch, Triton und AITER. Für genau dieses Setup gibt es
aber nicht genug belastbare Belege, die den Austausch des bekannten
funktionierenden Stands rechtfertigen.

Insbesondere gilt:

- v0.30.0 ersetzt nicht nachweislich beide lokalen ROCr-Workarounds
  vollständig. Der Null-Event-Workaround bleibt lokal.
- v0.30.0 verwendet AITER 0.1.21.post2 und liegt damit vor dem breiteren
  offiziellen RDNA-LDS-Guard aus AITER 0.1.23.
- Die fünf veröffentlichten GEMM-Tuningdateien wurden mit dem festgelegten
  v0.29.0-Stack gemessen. Ein anderer AITER-/Triton-/Kernel-Router kann die
  Dateien zwar syntaktisch akzeptieren, ohne dass ihre Performanceaussage noch
  gilt.
- Ein großer Teil der auffälligen ROCm-Arbeit in v0.30.0 betrifft CDNA, MoE,
  Sparse Attention oder andere Modelle. Diese Ergebnisse lassen sich nicht
  ohne direkte Messung auf das dichte Qwen3.8-27B-FP8 übertragen.

Die Entscheidung lautet deshalb **überspringen**, nicht „v0.30.0 ist defekt“.
Für andere Hardware und Lastprofile kann das Release sinnvoll sein; es erfüllt
nur die Upgrade-Schwelle dieses Projekts nicht.

## Was v0.31.x ursprünglich für uns interessant machte

Die folgenden Punkte waren die ursprüngliche Beobachtungsliste nach v0.30. Sie
bleiben als historischer Kontext nützlich; die aktuelle Entscheidung und der
Nightly-Stand nach v0.31 stehen oben. Ein offener Pull Request ist keine
Zusage, dass die Änderung in v0.32.0 erscheint.

### Bereits auf vLLM main

- **AITER 0.1.23:**
  [vLLM #58867](https://github.com/vllm-project/vllm/pull/58867) hat das
  Versionsupdate zusammengeführt. AITER 0.1.23 enthält den breiteren
  offiziellen
  [RDNA-Unified-Attention-LDS-Guard](https://github.com/ROCm/aiter/pull/4868),
  einschließlich `gfx1201`. Das ist der erste glaubwürdige Upstream-Ersatz für
  unseren lokalen AITER-LDS-Backport. Entfernt werden sollte dieser trotzdem
  erst nach einem Test des exakten Images, Modells, Graph-Capture-Pfads,
  Langkontexts und Durchsatzes.

### Offene Kandidaten mit direktem Bezug

- **Nativer W8A8-FP8-HIP-GEMM für gfx1201:**
  [vLLM #58238](https://github.com/vllm-project/vllm/pull/58238) schlägt einen
  optionalen Kernel für Prefill und Decode vor. Der veröffentlichte Test nutzt
  zwei R9700 und Qwen3-32B-FP8 statt unseres exakten Modells. Bei Concurrency
  16 werden ungefähr 25 % niedrigere mittlere TPOT und 43 % niedrigere
  mittlere TTFT angegeben. Das ist sehr relevant, aber noch kein
  Qwen3.8-27B-Einzelrequesttest.
- **Split-KV-Decode-Attention für RDNA3/RDNA4:**
  [vLLM #58156](https://github.com/vllm-project/vllm/pull/58156) zielt auf den
  Long-Context-Decode-Engpass und verwendet Qwen3.8-27B-TP2-Formen. Die
  angegebenen Beschleunigungen von 4,9x bis 19,1x sind reine Kernelmessungen
  auf `gfx1100`, kein End-to-End-Durchsatz auf der R9700.
- **Native HIP-All-Reduce-Implementierung für RDNA3/RDNA4:**
  [vLLM #57767](https://github.com/vllm-project/vllm/pull/57767) unterstützt
  TP=2 und TP=4 beim Decode auf `gfx1201`. Der veröffentlichte
  R9700-End-to-End-Spitzenwert stammt aber von einem BF16-MoE-TP4-Lastprofil;
  der Gewinn für dichtes FP8 mit TP=2 ist noch nicht belegt.
- **RDNA4-FlyDSL-GEMMs für blockskaliertes FP8:**
  [vLLM #56005](https://github.com/vllm-project/vllm/pull/56005) zielt
  ausdrücklich auf `Qwen3.8-27B-FP8`-Formen auf der R9700. Alle 18
  veröffentlichten Kerneltests waren schneller als Triton, im geometrischen
  Mittel 1,786x. Es fehlt aber ein End-to-End-Serving-Ergebnis und FlyDSL ist
  eine zusätzliche Abhängigkeit.

Diese Kandidaten sind für uns interessanter als die Versionsnummer v0.30.0,
weil sie die tatsächliche Hardware und die Engpässe dieses Repositorys treffen.

## Vorläufiger Patchplan für v0.32.0 (Stand 16.10.2026)

Diese Bewertung bezieht sich auf den derzeitigen
[`releases/v0.32.0`-Branch](https://github.com/vllm-project/vllm/tree/releases/v0.32.0),
nicht auf ein bereits auf diesem System validiertes finales Release-Image. Der
erste Test wird deshalb absichtlich mit dem **unveränderten offiziellen Image**
durchgeführt: ohne die drei lokalen Patches und zunächst auch ohne die fünf
lokalen GEMM-Tuningdateien. Nur ein auf diesem Aufbau reproduziertes Problem
rechtfertigt einen neuen Patch.

| Bisherige lokale Änderung | Stand im aktuellen v0.32-Branch | Geplantes Vorgehen |
| --- | --- | --- |
| AITER-LDS-Guard | Der Branch baut [AITER 0.1.24.post1](https://github.com/vllm-project/vllm/blob/releases/v0.32.0/docker/Dockerfile.rocm_base); der allgemeinere RDNA-LDS-Guard aus [ROCm/aiter #4868](https://github.com/ROCm/aiter/pull/4868) ist darin enthalten. | Den lokalen Backport zunächst weglassen und Kaltstart sowie Unified Attention direkt auf `gfx1201` prüfen. |
| ROCr-AsyncEventsLoop-Backoff | Die frühere Upstream-Implementierung ist Commit [`46558b7`](https://github.com/ROCm/rocm-systems/commit/46558b7af4dc79b8b8014619c1afdb82db079a9f). Der aktuell gepinnte ROCr-Quellstand enthält den lokalen 20–200-µs-Backoff nicht; der offizielle Folgecommit [`867d8de`](https://github.com/ROCm/rocm-systems/commit/867d8def53f68bbb892b4fd5605eff727eab6c0f) aus [#13149](https://github.com/ROCm/rocm-systems/pull/13149) entfernt diesen Backoff auf interruptfähigem nativem Linux wieder, weil er in gemischten Signal-Batches Latenz erzeugt. | Nicht übernehmen. |
| ROCr-Null-Event-Backoff | Der Backoff behandelt das Polling-Symptom und besitzt den dokumentierten Decode-Zielkonflikt. Eine inzwischen lokalisierte mögliche Ursache ist die Erschöpfung aller KFD-Events durch den Signal-Pool des `rocprofiler-sdk`. | Nicht vorsorglich übernehmen. Erst das nackte Image auf Idle-CPU und fehlende Events prüfen. |

### Möglicher verbleibender Root-Cause-Patch

Der vom v0.32-Branch gepinnte `rocprofiler-sdk` reserviert beim ersten
Pool-Aufbau weiterhin 4096 interruptfähige HSA-Signale. Das entspricht dem
gesamten KFD-Event-Limit eines Prozesses und passt zu den in diesem Projekt
gemessenen Werten `checked_out_highwater=4094` und `create_failure=1`.
[ROCm/rocm-systems #13177](https://github.com/ROCm/rocm-systems/issues/13177)
lokalisiert diesen Zusammenhang; der noch offene
[Root-Cause-Patch #13179](https://github.com/ROCm/rocm-systems/pull/13179)
verkleinert den Pool-Batch von 4096 auf 1024.

**Quelltext- und Lesbarkeitshinweis:** Der Ausgangswert steht im Upstream-Code
als `constexpr size_t default_signal_pool_size = (1 << 12);`. Das ergibt zwar
denselben Maschinenwert wie `4096`, ist an dieser Stelle aber unnötig
verschleiernd: Es geht um die konkrete Anzahl reservierter Signale, nicht um
eine Bitmaske oder ein Bitfeld. `4096` würde die fachliche Bedeutung unmittelbar
zeigen und die auffällige Übereinstimmung mit dem KFD-Event-Limit bei Reviews
sichtbarer machen. Diese schlechte Schreibweise ist für sich allein kein
Ursachennachweis, erschwert aber genau die menschliche Prüfung solcher
Grenzwertfehler.

Dieser kleine `rocprofiler-sdk`-Patch ist der einzige derzeit erkennbare
Patchkandidat für v0.32.0. Er wird trotzdem **nicht prophylaktisch** eingebaut.
Nur wenn das unveränderte Release-Image erneut dauerhafte Idle-CPU-Last zeigt
und die Event-Erschöpfung bestätigt wird, soll genau dieser Root-Cause-Patch
isoliert getestet werden. Die beiden alten ROCr-Backoffs sollen dadurch nicht
in ein v0.32-Image übernommen werden.

## Regel für die Übernahme der Tunings

Die fünf v0.29.0-Tuning-JSONs sind nur für den festgelegten v0.29.0-Stack ein
Performancebeleg. Der
[v0.32-Config-Loader](https://github.com/vllm-project/vllm/blob/releases/v0.32.0/vllm/model_executor/layers/quantization/utils/fp8_utils.py)
verwendet weiterhin denselben Pfad, Dateinamen und dasselbe JSON-Schema für
`fp8_w8a8` mit Blockform `[128,128]`; die Dateien sind daher mechanisch
kompatibel. Das beweist aber weder, dass der Dispatcher diesen Kernelpfad im
konkreten Lauf auswählt, noch dass die alten Gewinner unter dem neuen
PyTorch-/Triton-/vLLM-Stack weiterhin optimal sind.

Der Prüfablauf lautet deshalb: zuerst v0.32 ohne lokale Configs, anschließend
dasselbe Image mit den fünf alten JSONs und danach eine vollständige
Neuvermessung. Dabei muss man:

1. feststellen, welches GEMM-Backend die einzelnen Modellformen tatsächlich
   erhält;
2. prüfen, ob ein neuer nativer HIP- oder FlyDSL-Pfad das alte AITER-Tuning
   umgeht;
3. jede getunte Form auf beiden GPUs erneut gegen den neuen Standard messen;
4. HIP-Graph- und TP2-Stresstests wiederholen;
5. neue Tuningdateien nur veröffentlichen, wenn sie reproduzierbar gewinnen.

Die alten Dateien dürfen damit als Kompatibilitäts- und Vergleichskandidaten
dienen. Sie lediglich in ein neues Image zu kopieren und ungeprüft als
„v0.32-Tuning“ zu veröffentlichen ist weder ein gültiger Benchmark noch eine
gültige Migration. Das optionale `ROCM_SEGMENTED_ATTN` besitzt außerdem einen
eigenen Attention-Autotuning-Cache; dieser ist von den fünf GEMM-JSONs getrennt.

## Upgrade-Schranke

Ein zukünftiges stabiles v0.32.0 sollte isoliert getestet und nicht über das
funktionierende Image installiert werden. Ein Upgrade wird erst dann
vorbereitenswert, wenn das Release materiell relevante Änderungen wie die oben
genannten enthält und auf dem exakten Produktivhost alle folgenden Prüfungen
besteht:

- Kaltstart und AITER-LDS-Validierung;
- exakte historische Request-Replays einschließlich langer
  Reasoning-Antworten;
- Vergleich von Decode-Durchsatz, TTFT und Prefix Cache;
- MTP-Vergleich an/aus mit derselben Einstellung von zwei spekulativen Tokens;
- TP2-Korrektheit und längerer Stresstest;
- Leerlauf-CPU- und Leistungsmessung nach der RCCL-Initialisierung;
- Prüfung, welche lokalen Patches noch erforderlich sind;
- neue Messung von GEMM-Backend-Auswahl und Tunings.

Bis dahin lautet die Empfehlung dieses Repositorys: v0.29.0 im
Produktivbetrieb beibehalten und ein v0.32-Entwicklungsimage nur separat im
Labor testen.
