# Sherpa Swahili TTS Engine

This repository contains a manually triggered GitHub Actions build for one
Android Text-to-Speech engine APK. It deliberately does not fork or vendor
[`k2-fsa/sherpa-onnx`](https://github.com/k2-fsa/sherpa-onnx): each build makes
a disposable, pinned upstream checkout, configures its stock TTS-engine template
for one Swahili Piper model, and packages only `arm64-v8a` native libraries.

## Pinned inputs

| Input | Pinned value |
| --- | --- |
| sherpa-onnx | `v1.13.1` / `f3b1a9da8d6e0e6cdb21387d41d25f8c8e10d3cc` |
| Model release | `tts-models` |
| Piper model | `vits-piper-sw_CD-lanfrica-medium` |
| Model file | `sw_CD-lanfrica-medium.onnx` |
| ABI | `arm64-v8a` |
| Java | Temurin 17 |
| Android platform / build tools | 34 / 34.0.0 |
| Android NDK | 28.2.13676358 |
| Android CMake | 3.22.1 |

The generated engine configuration is:

```text
modelName = sw_CD-lanfrica-medium.onnx
modelDir  = vits-piper-sw_CD-lanfrica-medium
dataDir   = vits-piper-sw_CD-lanfrica-medium/espeak-ng-data
lang      = swa
lexicon   = null
```

The APK retains upstream’s package identity
`com.k2fsa.sherpa.onnx.tts.engine`, with version code `20260508` and version
name `1.13.1`. It contains `libsherpa-onnx-jni.so`, `libonnxruntime.so`, the
single ONNX model, and its `espeak-ng-data` assets.

## Build and download

1. Open **Actions** in this repository.
2. Select **Build Swahili TTS Engine APK**.
3. Click **Run workflow** on `main`.
4. When the run passes, download the
   `sherpa-swahili-tts-engine-debug-arm64-v8a` artifact. It contains the APK and
   its `.sha256` file.

The workflow is `workflow_dispatch` only. It has read-only repository-token
permissions, does not create a Release, and does not create QR links.

For a local build, install the pinned Android SDK components, set `ANDROID_NDK`
to the NDK 28.2.13676358 directory (and `ANDROID_HOME` if build tools are not
on `PATH`), then run:

```bash
./scripts/build-swahili-tts-apk.sh
```

The output is `artifacts/SherpaSwahiliTtsEngine-v1.13.1-arm64-v8a-debug.apk`.
The script refuses to overwrite an existing `.build` directory, removes its own
temporary checkout on exit, and never uses the upstream multi-model generator.

## Galaxy S25 installation

The S25 is arm64-compatible. Transfer the downloaded debug APK, enable the
installer app as an allowed source for unknown apps if Android asks, install it,
then select **TTS Engine: Next-gen Kaldi** in Android’s Text-to-speech output
settings. Choose Swahili and use the system’s **Play** control to test speech.

This is a debug-signed APK. Android accepts it for development/sideloading, but
it is not suitable for production distribution. A later production release must
use a stable, protected release-signing key and an explicitly planned package
identity/update path. Device synthesis has not been verified by this repository
workflow.

## Licensing and attribution

sherpa-onnx is distributed under the Apache License 2.0; preserve its required
license and notice material when redistributing derived APKs. The downloaded
model is supplied by the upstream `tts-models` release. Its `MODEL_CARD` and
any model-specific upstream license, attribution, acceptable-use, and
redistribution terms must be reviewed and satisfied before public redistribution.
This build repository intentionally does not claim rights beyond those supplied
by the upstream projects and model authors.
