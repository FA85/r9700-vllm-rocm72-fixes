# Authorship and motivation disclaimer

## Deutsch

Jedes Byte des eigenständigen Projektcodes in diesem Repository wurde von
OpenAI Codex im Auftrag und in Zusammenarbeit mit FA85 geschrieben. Dazu
gehören insbesondere das Containerfile, die Patch-Anwendungsskripte sowie die
Build-, Prüf- und Startskripte.

Entstanden ist das Projekt aus zwei sehr praktischen Gründen: FA85 war mit der
Performance des unveränderten vLLM-ROCm-Standardimages unzufrieden und wollte
deshalb den AITER-Pfad auf der Radeon AI PRO R9700 zuverlässig nutzen. Daraus
entstand der AITER-LDS-Backport. Anschließend zeigte sich eine ungewöhnlich
hohe CPU-Last im Leerlauf. Der damit verbundene Stromverbrauch — und letztlich
eine schlicht zu hohe Stromrechnung — war der Anlass, die beiden ROCr-Backoffs
zu diagnostizieren und umzusetzen.

„Jedes Byte des eigenständigen Projektcodes“ bedeutet nicht, dass Codex oder
FA85 Urheberschaft an vLLM, ROCm/ROCr, AITER, dem Basisimage oder anderem
Drittanbietercode beanspruchen. Teile der Patchlogik sind aus den im Repository
genannten Upstream-Änderungen abgeleitet. Sämtliche Rechte, Copyrightvermerke,
Marken und Lizenzen der jeweiligen Upstream-Projekte bleiben unberührt. Details
stehen in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Das Projekt ist inoffiziell, wird ohne Gewähr bereitgestellt und wird weder von
AMD noch von vLLM, ROCm oder AITER unterstützt oder empfohlen.

## English

Every byte of original project code in this repository was written by OpenAI
Codex at the direction of and in collaboration with FA85. This includes the
Containerfile, patch-application scripts, and the build, verification, and
launcher scripts.

The project grew out of two practical concerns. FA85 was dissatisfied with the
performance of the unmodified standard vLLM ROCm image and wanted to use the
AITER path reliably on the Radeon AI PRO R9700; this led to the AITER LDS
backport. The system then exhibited unusually high idle CPU usage. The
resulting power consumption — and, ultimately, an electricity bill that was
simply too high — motivated the diagnosis and implementation of the two ROCr
backoffs.

“Every byte of original project code” does not claim authorship of vLLM,
ROCm/ROCr, AITER, the base image, or any other third-party code. Parts of the
patch logic are derived from the upstream changes referenced by this
repository. All upstream copyrights, trademarks, and licenses remain with
their respective owners. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for details.

This is an unofficial project provided without warranty. It is not supported
or endorsed by AMD, vLLM, ROCm, or AITER.
