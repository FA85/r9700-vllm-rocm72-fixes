# Authorship and motivation disclaimer

## Deutsch

Jedes Byte des eigenständigen Projektcodes in diesem Repository wurde von
verschiedenen ChatGPT-Codex-Modellen im Auftrag und in Zusammenarbeit mit FA85
geschrieben. FA85 navigierte, untersuchte und testete die Ergebnisse über
mehrere Wochen. Zum Projektcode gehören insbesondere das Containerfile, die
Patch-Anwendungsskripte sowie die Build-, Prüf- und Startskripte.

Entstanden ist das Projekt aus zwei sehr praktischen Gründen: FA85 war mit der
Performance des unveränderten vLLM-ROCm-Standardimages unzufrieden: Beobachtet
wurden etwa 9,6 tok/s bei 50 % KV-Auslastung. Der Wunsch, stattdessen den
AITER-Pfad auf der Radeon AI PRO R9700 zuverlässig zu nutzen, führte zum
AITER-LDS-Backport. Anschließend zeigte sich eine ungewöhnlich hohe CPU-Last im
Leerlauf. Der damit verbundene Stromverbrauch — und letztlich eine schlicht zu
hohe, selbst zu bezahlende Stromrechnung — war der Anlass, die beiden ROCr-
Backoffs zu diagnostizieren und umzusetzen. Das resultierende Dual-R9700-Setup
läuft nach FA85s Beobachtung mit 50–70 tok/s. Diese Werte sind
setupspezifische Beobachtungen und kein standardisierter Benchmark. Spätere
kontrollierte Replays ordneten dem Null-Event-Backoff bei längeren Antworten
eine reproduzierbare Regression von Referenzwerten um 55–58 tok/s auf etwa
41–44 tok/s zu. Der Zielkonflikt zwischen niedrigerer CPU-Last und Decode-
Durchsatz ist in [KNOWN_PERFORMANCE_TRADEOFF.md](KNOWN_PERFORMANCE_TRADEOFF.md)
dokumentiert; ein separates Ersatz-Image ohne diesen Backoff wird nicht
angeboten.

„Jedes Byte des eigenständigen Projektcodes“ bedeutet nicht, dass Codex oder
FA85 Urheberschaft an vLLM, ROCm/ROCr, AITER, dem Basisimage oder anderem
Drittanbietercode beanspruchen. Teile der Patchlogik sind aus den im Repository
genannten Upstream-Änderungen abgeleitet. Sämtliche Rechte, Copyrightvermerke,
Marken und Lizenzen der jeweiligen Upstream-Projekte bleiben unberührt. Details
stehen in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Das Projekt ist inoffiziell, wird ohne Gewähr bereitgestellt und wird weder von
AMD noch von vLLM, ROCm oder AITER unterstützt oder empfohlen.

## English

Every byte of original project code in this repository was written by various
ChatGPT Codex models at the direction of and in collaboration with FA85. FA85
navigated, investigated, and tested the results over several weeks. The
project code includes the Containerfile, patch-application scripts, and the
build, verification, and launcher scripts.

The project grew out of two practical concerns. FA85 was dissatisfied with the
performance of the unmodified standard vLLM ROCm image, observing about 9.6
tok/s at 50% KV utilization. The desire to use the AITER path reliably on the
Radeon AI PRO R9700 led to the AITER LDS backport. The system then exhibited
unusually high idle CPU usage. The resulting power consumption — and,
ultimately, an electricity bill that FA85 had to pay and that was simply too
high — motivated the diagnosis and implementation of the two ROCr backoffs.
FA85 observes 50–70 tok/s with the resulting dual-R9700 setup. These numbers
are setup-specific observations, not a standardized benchmark. Later
controlled replays attributed a reproducible long-response regression from
reference results around 55–58 tok/s to about 41–44 tok/s to the null-event
backoff. The lower-CPU-versus-decode-throughput trade-off is documented in
[KNOWN_PERFORMANCE_TRADEOFF.md](KNOWN_PERFORMANCE_TRADEOFF.md); no separate
replacement image without that backoff is provided.

“Every byte of original project code” does not claim authorship of vLLM,
ROCm/ROCr, AITER, the base image, or any other third-party code. Parts of the
patch logic are derived from the upstream changes referenced by this
repository. All upstream copyrights, trademarks, and licenses remain with
their respective owners. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for details.

This is an unofficial project provided without warranty. It is not supported
or endorsed by AMD, vLLM, ROCm, or AITER.
