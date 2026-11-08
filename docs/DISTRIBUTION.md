# GrainAgent 1.0.1 — distribution

**Build 29** is the accepted formal release for **Apple Silicon (M-series),
macOS 14 Sonoma or later**. User acceptance passed on macOS 14 and macOS 15.
The [public release](https://github.com/RichardCarolJ/GrainAgent/releases/tag/v1.0.1)
provides the application, corresponding source and SHA-256 hashes. The user-accepted app is packaged together with the approved
bilingual quick-start PDF.

## Download and installation

Use the [Mac application ZIP in the v1.0.1 release](https://github.com/RichardCarolJ/GrainAgent/releases/tag/v1.0.1),
extract it, and move GrainAgent.app into Applications. The ZIP contains only
the app and `GrainAgent-Quick-Start.pdf`. The app contains its
native engine and required data; no Python, separate service or development
checkout is needed. Intel Macs and Windows are not included in this release.

The signature is **ad-hoc**, not Developer ID signed or Apple notarized.
If macOS blocks the first launch, follow Apple’s per-app
[Open Anyway procedure](https://support.apple.com/en-us/102445) after confirming
the download source. Do not disable system security globally. An ad-hoc
signature checks integrity, not an Apple-verified publisher identity.

Native Liquid Glass is used where available on macOS 26+. macOS 14/15 use the
existing native translucent-material path, with the same controls and engine.
English, Simplified Chinese, French and Spanish are included. First launch
follows the primary system language, with English as the fallback; Settings
can override that choice. The optional in-app update checker remains disabled.

## Source and licences

The release provides the app-and-guide ZIP, its exact corresponding-source ZIP,
and a SHA-256 file for each. The same source ZIP is embedded at
`GrainAgent.app/Contents/Resources/CorrespondingSource.zip` and can be revealed
from About GrainAgent. It includes the modified source, build scripts, required
resources, licence texts and a SHA-256 file manifest.

The `v1.0.1` tag identifies this public release. The corresponding-source ZIP
includes a `SOURCE-MANIFEST.json` for the accepted build. The repository also
contains the current documentation, quick-start guide and packaging script.

- Code: GPL-3.0-or-later, retaining upstream copyright, licence and modification
  notices and supplying corresponding source alongside the binary.
- spektrafilm profiles and derived print LUTs: CC BY-SA 4.0, retaining attribution,
  the supplied licence and transformation history.
- Other dependencies retain their original licences. Product-profile lineage
  is recorded separately. Code and data licences do not grant trademark rights.
- The showcase photographs remain Richard Jin’s work and are not
  relicensed by the code licence. See [showcase credits](SCREENSHOT-CREDITS.md).

See [NOTICE.md](../NOTICE.md), [LICENSE.txt](../LICENSE.txt), the complete
[supplied data notice](../license/SPEKTRAFILM_LICENSE.txt) and
[data provenance](../license/UPSTREAM-DATA-PROVENANCE.txt).
The relevant licence texts are [GNU GPL v3](https://www.gnu.org/licenses/gpl-3.0.html)
and [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).
No new CLA, DCO, commercial restriction or account requirement is introduced.

## Clean-package boundary

`BuildSupport/ReleaseResources.json` is the reviewed 81-file runtime inventory.
Packaging rejects unexpected runtime files, unreviewed images, photo sidecars,
caches and obsolete helper executables. Finder metadata, resource forks and
quarantine attributes are excluded from the ZIPs. The unused upstream editor,
export windows, packaging photographs and icon layers have been removed from
the active product; the native engine and required data remain intact.

No original RAW photographs, photo library, local preferences or work-recovery
records are included in the application or the matching source ZIP. The PDF guide
contains small, retouched interface illustrations using Richard Jin’s photographs.
A fresh Mac starts with an empty photo list; an existing installation can restore
that Mac’s own saved work.

The raw files used for the README illustrations are not uploaded. GitHub’s
automatic archive of `main` includes repository documentation images, while the
separately provided corresponding-source ZIP excludes them.

See the [public version history](https://github.com/RichardCarolJ/GrainAgent/blob/main/CHANGELOG.md) for user-facing changes.
