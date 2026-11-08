# GrainAgent — attribution and modification notice

GrainAgent 1.0.1 is an independent modified version of SpektraLab 1.3.5.
GrainAgent interface and workflow modifications: Richard Jin, 2026.
Modification period: 2026-11-05 through 2026-11-07 (Australia/Darwin).

## Application and native implementation

SpektraLab by Hanze Qiu and its contributors provides the native application,
C++/Metal engine port, decoding and colour-management integration, editing
models, film-edge/date-back features and export implementation used here.
Upstream: https://github.com/JamesQiu2005/SpektraLab
Pinned base: 02d82b56cf65f0f8e802a708612edc4e9a4790af (spektralab-v1.3.5).
Application and engine code: GNU GPL version 3 or any later version.
The complete licence is LICENSE.txt; upstream notices remain in the source.

GrainAgent replaces the workspace with a camera-inspired simple mode and a
Liquid Glass professional mode; adds shared batch output, per-photo simple
mode state, selective application/undo, workspace recovery and independent
product identity. It does not claim authorship of the underlying spectral
model or the native engine port. See SOURCE-MANIFEST.json in the accompanying source archive for the exact included files.

## Film model and original data

Andrea Volpato's spektrafilm supplies the spectral film/print model and the
original measured film/paper profiles.
Canonical source: https://github.com/andreavolpato/spektrafilm
Reference implementation: GPL-3.0-or-later.
Original profiles and derived print-preview LUTs: CC BY-SA 4.0.
The attribution, complete supplied licence and data transformation notice are
retained in license/SPEKTRAFILM_LICENSE.txt and Resources/Licenses/.
GrainAgent has not modified the inherited engine, profiles or print LUTs.
SpektraLab's additional product profiles, aliases and measured/fitted data
keep their separate provenance notice in engine/resources_product/NOTICE.md;
they are not attributed to Andrea Volpato as newly measured work.
The resource lineage and upstream's treatment of the other baked colour-science
tables are recorded in license/UPSTREAM-DATA-PROVENANCE.txt. The supplied
upstream licence texts and profile/LUT transformation notice are retained.

## Other dependencies and visual assets

Apple metal-cpp: Apache-2.0; see engine/third_party/metal-cpp/LICENSE.txt.
System Apple frameworks are supplied by macOS.

GrainAgent's approved camera icon, brushed-metal/leather textures and new
film-canister illustrations were produced for this project with AI-assisted
image generation and local image processing. They are illustrations, not
photographs supplied or endorsed by film manufacturers. Their included
modifiable files and any rights held in GrainAgent-created visual work are
provided with the project under GPL-3.0-or-later. This does not purport to grant
rights held by third parties. Inherited assets retain their upstream notices.
Unused upstream JPEG packaging covers, the upstream icon document/layers and
the unused library-helper executable are excluded from this distribution.
BuildSupport/ReleaseResources.json inventories the retained UI resources.
No personal/test photographs, edit sidecars or workspace-recovery files are
included in the application or the corresponding source archive.

Film manufacturer names, packaging marks, SpektraLab and spektrafilm identify
their respective products/projects. No trademark rights or endorsement are
granted by these source-code or data licences. GrainAgent is not an official
release of, or endorsed by, either upstream project.

## Corresponding source and warranty

This standalone distribution includes its corresponding source archive at
GrainAgent.app/Contents/Resources/CorrespondingSource.zip. About GrainAgent
provides a button to reveal it. It includes the modified source, required
resources, build scripts, licences and file hashes; it contains no user photo
library or development workspace state. The source repository is https://github.com/RichardCarolJ/GrainAgent.
Each distribution is accompanied by the exact corresponding source ZIP and
SHA-256 checksums for its build number. Consult the release assets and the
SOURCE-MANIFEST.json inside that archive to identify the files for the build.

This software is provided without warranty under the applicable licences.
These notices preserve upstream credit and do not replace the licence texts.

## Showcase photographs

The README and quick-start guide illustrations use photographs supplied by Richard
Jin. Photograph rights remain with Richard Jin; the code and data licences do
not relicense those photographs. The original RAW files are not published, and
the illustrations appear in the README and the PDF guide.
[Showcase credits](docs/SCREENSHOT-CREDITS.md) describe the presentation edits.
