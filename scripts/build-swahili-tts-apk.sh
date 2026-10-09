#!/usr/bin/env bash
# Builds one disposable upstream checkout into the Swahili arm64-v8a debug APK.
set -euo pipefail

readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly BUILD_ROOT="${BUILD_ROOT:-${REPOSITORY_ROOT}/.build}"
readonly UPSTREAM_DIR="${BUILD_ROOT}/sherpa-onnx"
readonly ENGINE_DIR="${BUILD_ROOT}/SherpaOnnxTtsEngine"
readonly ARTIFACT_DIR="${REPOSITORY_ROOT}/artifacts"
readonly UPSTREAM_REPOSITORY="https://github.com/k2-fsa/sherpa-onnx.git"
readonly UPSTREAM_REVISION="f3b1a9da8d6e0e6cdb21387d41d25f8c8e10d3cc"
readonly MODEL_DIRECTORY="vits-piper-sw_CD-lanfrica-medium"
readonly MODEL_FILE="sw_CD-lanfrica-medium.onnx"
readonly MODEL_ARCHIVE="${MODEL_DIRECTORY}.tar.bz2"
readonly MODEL_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/${MODEL_ARCHIVE}"
readonly APK_NAME="SherpaSwahiliTtsEngine-v1.13.1-arm64-v8a-debug.apk"
readonly PACKAGE_NAME="com.k2fsa.sherpa.onnx.tts.engine"
readonly VERSION_CODE="20260508"
readonly VERSION_NAME="1.13.1"

require_command() {
  command -v "$1" >/dev/null || {
    echo "Required command not found: $1" >&2
    exit 1
  }
}

for command in git curl tar cmake make python3 unzip sha256sum; do
  require_command "$command"
done

: "${ANDROID_NDK:?Set ANDROID_NDK to Android NDK 28.2.13676358.}"
if [[ ! -f "${ANDROID_NDK}/build/cmake/android.toolchain.cmake" ]]; then
  echo "ANDROID_NDK does not contain the Android CMake toolchain: ${ANDROID_NDK}" >&2
  exit 1
fi

if [[ -e "${BUILD_ROOT}" ]]; then
  echo "Build root already exists: ${BUILD_ROOT}" >&2
  echo "Remove it explicitly or set BUILD_ROOT to an empty disposable directory." >&2
  exit 1
fi

mkdir -p "${BUILD_ROOT}" "${ARTIFACT_DIR}"
trap 'rm -rf "${BUILD_ROOT}"' EXIT

git clone --recursive "${UPSTREAM_REPOSITORY}" "${UPSTREAM_DIR}"
git -C "${UPSTREAM_DIR}" checkout --detach "${UPSTREAM_REVISION}"
git -C "${UPSTREAM_DIR}" submodule update --init --recursive

actual_revision="$(git -C "${UPSTREAM_DIR}" rev-parse HEAD)"
if [[ "${actual_revision}" != "${UPSTREAM_REVISION}" ]]; then
  echo "Unexpected sherpa-onnx revision: ${actual_revision}" >&2
  exit 1
fi

# The app project is copied into the disposable build directory so tracked upstream
# source remains untouched. Only this copy receives the single-model configuration.
cp -a "${UPSTREAM_DIR}/android/SherpaOnnxTtsEngine" "${ENGINE_DIR}"
# Upstream's Tts.kt is a relative symlink into the adjacent kotlin-api tree.
# Materialize it in this copied project so the isolated Gradle build remains valid.
rm -f "${ENGINE_DIR}/app/src/main/java/com/k2fsa/sherpa/onnx/tts/engine/Tts.kt"
cp -L "${UPSTREAM_DIR}/android/SherpaOnnxTtsEngine/app/src/main/java/com/k2fsa/sherpa/onnx/tts/engine/Tts.kt" \
  "${ENGINE_DIR}/app/src/main/java/com/k2fsa/sherpa/onnx/tts/engine/Tts.kt"

engine_source="${ENGINE_DIR}/app/src/main/java/com/k2fsa/sherpa/onnx/tts/engine/TtsEngine.kt"
python3 - "${engine_source}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
old = '''        // For VITS -- begin
        modelName = null
        // For VITS -- end

        // For Matcha -- begin
        acousticModelName = null
        vocoder = null
        // For Matcha -- end

        // For Kokoro -- begin
        voices = null
        // For Kokoro -- end

        modelDir = null
        ruleFsts = null
        ruleFars = null
        lexicon = null
        dataDir = null
        lang = null
        lang2 = null
'''
new = '''        // For VITS -- begin
        modelName = "sw_CD-lanfrica-medium.onnx"
        // For VITS -- end

        // For Matcha -- begin
        acousticModelName = null
        vocoder = null
        // For Matcha -- end

        // For Kokoro -- begin
        voices = null
        // For Kokoro -- end

        modelDir = "vits-piper-sw_CD-lanfrica-medium"
        ruleFsts = null
        ruleFars = null
        lexicon = null
        dataDir = "vits-piper-sw_CD-lanfrica-medium/espeak-ng-data"
        lang = "swa"
        lang2 = null
'''
if text.count(old) != 1:
    raise SystemExit("Unexpected upstream TtsEngine.kt template; refusing to patch it")
path.write_text(text.replace(old, new))
PY

assets_dir="${ENGINE_DIR}/app/src/main/assets"
archive_path="${BUILD_ROOT}/${MODEL_ARCHIVE}"
curl --fail --location --retry 3 --output "${archive_path}" "${MODEL_URL}"
tar -xjf "${archive_path}" -C "${assets_dir}"
rm -f "${archive_path}"

[[ -f "${assets_dir}/${MODEL_DIRECTORY}/${MODEL_FILE}" ]]
[[ -d "${assets_dir}/${MODEL_DIRECTORY}/espeak-ng-data" ]]

(
  cd "${UPSTREAM_DIR}"
  export ANDROID_NDK
  export SHERPA_ONNX_ENABLE_TTS=ON
  export SHERPA_ONNX_ENABLE_JNI=ON
  export SHERPA_ONNX_ENABLE_SPEAKER_DIARIZATION=OFF
  ./build-android-arm64-v8a.sh
)

native_lib_dir="${UPSTREAM_DIR}/build-android-arm64-v8a/install/lib"
for library in libsherpa-onnx-jni.so libonnxruntime.so; do
  [[ -f "${native_lib_dir}/${library}" ]]
done

jni_lib_dir="${ENGINE_DIR}/app/src/main/jniLibs/arm64-v8a"
mkdir -p "${jni_lib_dir}"
cp "${native_lib_dir}/libsherpa-onnx-jni.so" "${jni_lib_dir}/"
cp "${native_lib_dir}/libonnxruntime.so" "${jni_lib_dir}/"

(
  cd "${ENGINE_DIR}"
  ./gradlew --no-daemon assembleDebug
)

apk="${ENGINE_DIR}/app/build/outputs/apk/debug/app-debug.apk"
[[ -f "${apk}" ]]

if command -v aapt2 >/dev/null; then
  badging="$(aapt2 dump badging "${apk}")"
else
  : "${ANDROID_HOME:?Set ANDROID_HOME when aapt2 is not on PATH.}"
  badging="$("${ANDROID_HOME}/build-tools/34.0.0/aapt" dump badging "${apk}")"
fi
grep -F "package: name='${PACKAGE_NAME}' versionCode='${VERSION_CODE}' versionName='${VERSION_NAME}'" <<<"${badging}"

unzip -l "${apk}" | grep -F "assets/${MODEL_DIRECTORY}/${MODEL_FILE}"
unzip -l "${apk}" | grep -F "assets/${MODEL_DIRECTORY}/espeak-ng-data/"
unzip -l "${apk}" | grep -F "lib/arm64-v8a/libsherpa-onnx-jni.so"
unzip -l "${apk}" | grep -F "lib/arm64-v8a/libonnxruntime.so"

if command -v apksigner >/dev/null; then
  apksigner verify --verbose --print-certs "${apk}"
else
  : "${ANDROID_HOME:?Set ANDROID_HOME when apksigner is not on PATH.}"
  "${ANDROID_HOME}/build-tools/34.0.0/apksigner" verify --verbose --print-certs "${apk}"
fi

output_apk="${ARTIFACT_DIR}/${APK_NAME}"
output_checksum="${output_apk}.sha256"
cp "${apk}" "${output_apk}"
actual_checksum="$(sha256sum "${output_apk}" | awk '{print $1}')"
printf '%s  %s\n' "${actual_checksum}" "${APK_NAME}" > "${output_checksum}"
expected_checksum="$(awk '{print $1}' "${output_checksum}")"
[[ "${actual_checksum}" == "${expected_checksum}" ]]

echo "Built APK: ${output_apk}"
