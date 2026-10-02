# vLLM-Upgrade-Beobachtung: v0.30.0 überspringen, v0.31.x beobachten

[English version](UPGRADE_WATCH.md)

Stand: 02.10.2026.

Diese Notiz hält eine Projektentscheidung fest und ist keine allgemeine
Empfehlung für alle ROCm-Nutzer. Das Referenzsystem besteht aus:

- zwei AMD Radeon AI PRO R9700 (`gfx1201`) mit Tensor Parallelism 2;
- `Qwen/Qwen3.8-27B-FP8`, einem dichten blockskalierten FP8-Modell;
- dem von diesem Repository festgelegten vLLM-0.29.0-/ROCm-7.2.3-Image;
- AITER Unified Attention, fünf lokal gemessenen GEMM-Tuningdateien und MTP
  mit zwei spekulativen Tokens;
- den drei in diesem Repository dokumentierten lokalen Fixes.

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

## Was v0.31.x für uns interessant machen könnte

Zum Zeitpunkt dieser Notiz gab es noch kein stabiles v0.31.x. Die folgenden
Punkte sind Änderungen nach v0.30 auf `main` oder offene Pull Requests. Ein
offener Pull Request ist keine Zusage, dass die Änderung in v0.31.x erscheint.

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

## Stand der drei lokalen Fixes

| Lokale Änderung | Upstream-Stand | Folge für ein Upgrade |
| --- | --- | --- |
| AITER-LDS-Guard | Ein breiterer Fix ist mit [ROCm/aiter #4868](https://github.com/ROCm/aiter/pull/4868) in AITER 0.1.23 enthalten. | Nach direkter Validierung ein Kandidat zum Entfernen. |
| ROCr-AsyncEventsLoop-Backoff | [ROCm/rocm-systems #7898](https://github.com/ROCm/rocm-systems/pull/7898) wurde upstream zusammengeführt. | Vor dem Entfernen des Backports prüfen, ob die exakte ROCr-Quelle des Release-Images den Fix enthält. |
| ROCr-Null-Event-Backoff | Ein gleichwertiger Upstream-Fix ist nicht bekannt. [ROCm/rocm-systems #11170](https://github.com/ROCm/rocm-systems/pull/11170) betrifft `BusyWaitSignal`, nicht unseren Event-Erschöpfungs-/`InterruptSignal`-Pfad. | Bleibt ein lokaler Workaround mit dem dokumentierten Decode-Zielkonflikt. |

## Regel für die Übernahme der Tunings

Die fünf v0.29.0-Tuning-JSONs sind nur für den festgelegten v0.29.0-Stack ein
Beleg. Für einen v0.31.x-Kandidaten muss man:

1. feststellen, welches GEMM-Backend die einzelnen Modellformen tatsächlich
   erhält;
2. prüfen, ob ein neuer nativer HIP- oder FlyDSL-Pfad das alte AITER-Tuning
   umgeht;
3. jede getunte Form auf beiden GPUs erneut gegen den neuen Standard messen;
4. HIP-Graph- und TP2-Stresstests wiederholen;
5. neue Tuningdateien nur veröffentlichen, wenn sie reproduzierbar gewinnen.

Die alten Dateien lediglich in ein neues Image zu kopieren ist weder ein
gültiger Benchmark noch eine gültige Migration.

## Upgrade-Schranke

Ein zukünftiges stabiles v0.31.x sollte isoliert getestet und nicht über das
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
Produktivbetrieb beibehalten und ein v0.31.x-Entwicklungsimage nur separat im
Labor testen.
