# GrainAgent — development

This repository contains the application and native engine. See `Product.json`
for the version, build number and minimum macOS version.

## Build

Use an Apple Silicon Mac, an Apple toolchain with the macOS 26 SDK and Swift 6,
and Python 3 for build scripts. The application runtime target is macOS 14.0.

```sh
python3 Tools/build-local.py
python3 Tools/package-release.py
```

`build/GrainAgent.app` is the optimized app. `dist/` contains a versioned app ZIP,
an identical separately downloadable copy of its embedded corresponding source,
and SHA-256 files. Packaging does not publish. The signature is ad-hoc, without
Apple notarization. The built app uses macOS system libraries only.

The corresponding-source ZIP can build the app on its own. To recreate the
user download from that ZIP, pass the
[official PDF guide](https://github.com/RichardCarolJ/GrainAgent/blob/main/docs/GrainAgent-Quick-Start.pdf)
to `python3 Tools/package-release.py --guide /path/to/GrainAgent-Quick-Start.pdf`.

After adding/removing Swift or C++ sources, regenerate the Xcode project:

```sh
python3 modern_UI/Spektrafilm/Tools/gen-project.py
```

A resources-only rebuild refuses changed compiled inputs or a different
deployment target. Compiled C++ object cache keys include the target.

## Shared implementation

Paths below are relative to `modern_UI/Spektrafilm/Spektrafilm/`.

| Location | Responsibility |
| --- | --- |
| Workspace/ | Mode switching, professional layout, shared batch export, selection, history and workspace recovery |
| Windows/SimpleCameraWorkspace.swift | Simple-mode bridge and native preview |
| Resources/SimpleCamera/ | Simple-mode UI and translations |
| Import/ | Shared file picking and native decoding |
| Model/, Service/, Export/ | Shared parameters, native engine boundary, export encoding |
| Localization/, Resources/Localization/ | English, Chinese, French and Spanish |
| Workspace/ProControls.swift | OS-specific visual materials, with shared controls and bindings |

`engine/` retains the original native C++/Metal processing. Film/paper data,
shaders and imaging arithmetic are unchanged. Both interfaces use the same
Session and Exporter. Saved work lives in Application Support and preferences,
never inside the app bundle.

## Packaging boundary

`BuildSupport/ReleaseResources.json` is the reviewed runtime file/hash allowlist.
Unknown runtime files, unreviewed images, edit sidecars, caches and legacy helper
executables fail packaging. Documentation screenshots remain repository-only;
no personal or showcase photo is distributed in the app or source ZIP.

See [distribution status](docs/DISTRIBUTION.md), [build resources](BuildSupport/README.md)
and [attribution](NOTICE.md).

## Engine boundary

The app links the native Metal engine directly through
[`spk_engine.h`](engine/include/spektrafilm/spk_engine.h). The Swift adapter and
parameter model live in `Service/` and `Model/`. Engine calls return status
codes and expose errors via `spk_last_error`. Use the C header's ownership
rules for returned textures and buffers. Keep Swift's parameter serialization
and the engine's JSON schema in sync. The engine returns image data, while
the app's export layer handles file encoding.

The engine keeps its baked resources in `engine/resources/`, including the
spectral constants and print LUTs. `engine/tools/bake_resources.py` documents
their generation using the upstream Python reference. Normal builds use the
included data and need no upstream checkout. See the
[data provenance notes](license/UPSTREAM-DATA-PROVENANCE.txt) for the inputs
and their sources. Keep measured film and paper data separate from UI
adjustment behavior.

Engine-boundary notes are based on the
[SpektraLab 1.3.5 native-engine documentation](https://github.com/JamesQiu2005/SpektraLab/blob/02d82b56cf65f0f8e802a708612edc4e9a4790af/ARCHITECTURE.md#8-the-native-engine).

## Checks without a photo library

The Xcode project includes focused tests for the macOS workspace, parameters,
export and bundled licences. The standalone window-geometry and workspace-
recovery checks under `Tools/` require no photos or saved user state. With the
full Metal toolchain, `engine/build.sh tests` builds the native engine smoke
and schema/setup drivers.

## Rebuilding the Metal libraries

To regenerate the pinned Metal libraries using Apple's Metal toolchain:

```sh
engine/build.sh metallib
cp engine/resources/spektrafilm.metallib modern_UI/Spektrafilm/Spektrafilm/Resources/engine/spektrafilm.metallib
xcrun -sdk macosx metal -mmacos-version-min=14.0 -ffast-math -c modern_UI/Spektrafilm/Spektrafilm/Canvas/Shaders.metal -o engine/build/canvas.air
xcrun -sdk macosx metallib engine/build/canvas.air -o BuildSupport/Precompiled/default.metallib
```

Review and update the library hashes in BuildSupport/Precompiled/manifest.json,
BuildSupport/ReleaseResources.json and BuildSupport/MetalBuild.json after rebuilding.
Both libraries target macOS 14.0. Retain the compiler math settings when
rebuilding the supplied shaders.

## Release compatibility

GrainAgent 1.0.1 Build 29 targets Apple Silicon on macOS 14.0 or later and
passed testing on Macs running macOS 14 and 15. See the
[version history](https://github.com/RichardCarolJ/GrainAgent/blob/main/CHANGELOG.md) for changes and the
[public release](https://github.com/RichardCarolJ/GrainAgent/releases/tag/v1.0.1) for the published files and hashes.
