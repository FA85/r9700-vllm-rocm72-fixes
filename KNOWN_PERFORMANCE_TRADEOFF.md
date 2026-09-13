# Known performance trade-off: ROCr null-event backoff

## Deutsch

Der ROCr-Null-Event-Backoff ist **kein kostenloser Performance-Fix**. Er wurde
für einen auf dem Dual-R9700-System von FA85 beobachteten Sonderfall ergänzt:
Ein blockierender `InterruptSignal::WaitRelaxed`-Pfad hatte kein gültiges
KFD-Event und rief dadurch
`hsaKmtWaitOnEvent_Ext(nullptr, ...)` in einer engen Schleife auf. Der
Workaround senkt die dabei entstehende CPU-Last, indem er das Userspace-Signal
mit einem exponentiellen Sleep von 20 bis 200 Mikrosekunden abfragt.

Auf demselben System wurde anschließend eine reproduzierbare
Decode-Regression diesem Null-Event-Backoff zugeordnet. In den betroffenen
langen Antwortfällen lagen Referenzläufe bei etwa 54,8 bis 57,6 tok/s, während
warme Läufe mit dem Backoff nur etwa 41,0 bis 44,1 tok/s erreichten. Das
entspricht je nach Fall ungefähr 20 bis 29 Prozent weniger Decode-Durchsatz.
Kurze Werkzeugentscheidungen blieben in der beobachteten Testreihe weitgehend
unverändert bei etwa 49 bis 59 tok/s.

Der Effekt war kein einmaliger JIT- oder Kaltstarteffekt: Alle acht Prüfungen
bestanden, alle Requests meldeten Cache-Treffer, und die Zeit bis zum ersten
Token lag bei 0,3 bis 0,6 Sekunden. Ein Warmstart beseitigte die Regression
nicht. Das Muster passt dazu, dass zusätzliche Sleeps in vielen kurzen
Synchronisationsvorgängen während längerer autoregressiver Decode-Phasen
aufsummiert werden.

Dieses Repository bewahrt den Workaround und seine Entstehung als
reproduzierbares, setupgebundenes Experiment. Es wird **kein separates
Ersatz-Image ohne diesen Backoff** angeboten. Wer das Image baut, entscheidet
sich bewusst für den beobachteten niedrigeren CPU-Verbrauch im problematischen
Null-Event-Pfad und nimmt die auf diesem Setup gemessene Decode-Regression in
Kauf. Der AITER-LDS-Backport, die veröffentlichten GEMM-Tunings und der aus
ROCm/rocm-systems#7898 übernommene AsyncEventsLoop-Backoff sind durch diese
Zuordnung nicht als Ursache der Regression identifiziert.

Die Zahlen gelten nur für das dokumentierte Dual-R9700-, Qwen3.8-27B-FP8-,
TP=2-, vLLM-0.29.0- und ROCm-7.2.x-Setup. Sie sind kein allgemeiner Benchmark
für andere Modelle, Lastprofile oder Systeme.

## English

The ROCr null-event backoff is **not a performance-neutral fix**. It was added
for a condition observed on FA85's dual-R9700 system: a blocking
`InterruptSignal::WaitRelaxed` path had no valid KFD event and repeatedly
called `hsaKmtWaitOnEvent_Ext(nullptr, ...)` in a tight loop. The workaround
reduces the resulting CPU load by polling the userspace signal with an
exponential sleep from 20 to 200 microseconds.

Follow-up testing on the same system attributed a reproducible decode
regression to this null-event backoff. Affected long-response reference runs
reached about 54.8 to 57.6 tok/s, while warm runs with the backoff reached only
about 41.0 to 44.1 tok/s. Depending on the case, this is roughly 20 to 29
percent less decode throughput. Short tool-choice requests remained largely
unchanged at about 49 to 59 tok/s in the observed test series.

This was not a one-time JIT or cold-start effect: all eight checks passed, all
requests reported cache hits, and time to first token was 0.3 to 0.6 seconds.
A warm restart did not remove the regression. The pattern is consistent with
additional sleeps accumulating across many short synchronization operations
during longer autoregressive decode phases.

This repository preserves the workaround and its provenance as a reproducible,
setup-specific experiment. It does **not provide a separate replacement image
without the backoff**. Building the image therefore means knowingly trading
lower CPU use in the problematic null-event path for the decode regression
measured on this setup. This attribution does not identify the AITER LDS
backport, the published GEMM tuning files, or the AsyncEventsLoop backoff from
ROCm/rocm-systems#7898 as the cause of the regression.

These measurements apply only to the documented dual-R9700,
Qwen3.8-27B-FP8, TP=2, vLLM 0.29.0, and ROCm 7.2.x setup. They are not a
general benchmark for other models, workloads, or systems.
