#!/usr/bin/env bash
set -euo pipefail

OPENMW_COMMIT='f4bec41444214a7903bebd178389ca22ca13f646'
UPSTREAM_REPO='Andiweli/OpenMW-Android'
UPSTREAM_TAG='0.51.0-09'
UPSTREAM_APK='OpenMW.0.51-09.apk'
UPSTREAM_APK_SHA256='8acd5ae5e44c5702b449aaad8978a4e117772a655e4b119f20d860913036726e'
KOREAN_ENGINE_REPO='munument1/-KR-openmw'
KOREAN_ENGINE_COMMIT='aecc06a5807afacf17dccd37fb3cfc685ee580fd'
KOREAN_TOPIC_BLOB='4d5e8e5d72ed944fd3286615d9d50f04f2ff97b6'
KOREAN_SIDECAR_BLOB='b83eaf76d1047757214711fbd0074a03876bf6de'
KOREAN_ESM_BLOB='aa5c3e5dd74cab31aa1c17aad01a232bf057e727'
JOBS="${JOBS:-4}"

DEST='source/buildscripts/patches/kr-origin'
OUTDIR='native-artifacts'
LOG="$OUTDIR/korean-native-build.log"
mkdir -p "$DEST" "$OUTDIR" work/upstream
rm -f "$OUTDIR/libopenmw.so" "$OUTDIR/libopenmw.so.sha256" "$OUTDIR/page-size-report.txt"

fetch_patch() {
  local src="$1" dst="$2" expected="$3"
  gh api "repos/$KOREAN_ENGINE_REPO/contents/$src?ref=$KOREAN_ENGINE_COMMIT" --jq '.content' \
    | base64 --decode > "$dst"
  test -s "$dst"
  test "$(git hash-object "$dst")" = "$expected"
}

fetch_patch 'korean/patches/0001-cjk-topic-discovery.patch' "$DEST/0001-cjk-topic-discovery.patch" "$KOREAN_TOPIC_BLOB"
fetch_patch 'korean/patches/0002-utf8-bom-sidecars.patch' "$DEST/0002-utf8-bom-sidecars.patch" "$KOREAN_SIDECAR_BLOB"
fetch_patch 'korean/patches/0003-mixed-utf8-esm-reader.patch' "$DEST/0003-mixed-utf8-esm-reader.patch" "$KOREAN_ESM_BLOB"

printf '%s\n' \
  "$KOREAN_ENGINE_REPO@$KOREAN_ENGINE_COMMIT" \
  "topic=$KOREAN_TOPIC_BLOB" \
  "sidecar=$KOREAN_SIDECAR_BLOB" \
  "esm=$KOREAN_ESM_BLOB" > "$OUTDIR/korean-origin.txt"

gh release download "$UPSTREAM_TAG" --repo "$UPSTREAM_REPO" --pattern "$UPSTREAM_APK" --dir work/upstream --clobber
BASE_APK="work/upstream/$UPSTREAM_APK"
test "$(sha256sum "$BASE_APK" | awk '{print $1}')" = "$UPSTREAM_APK_SHA256"
OFFICIAL_SHA="$(unzip -p "$BASE_APK" lib/arm64-v8a/libopenmw.so | sha256sum | awk '{print $1}')"
printf '%s\n' "$OFFICIAL_SHA" > "$OUTDIR/upstream-libopenmw.sha256"

python3 - <<'PY'
from pathlib import Path
p = Path('source/buildscripts/CMakeLists.txt')
text = p.read_text(encoding='utf-8')
needle = '        python3 ${CMAKE_SOURCE_DIR}/patches/openmw051-final/apply-android-graphics-followup4.py <SOURCE_DIR>\n)'
replacement = '''        python3 ${CMAKE_SOURCE_DIR}/patches/openmw051-final/apply-android-graphics-followup4.py <SOURCE_DIR> &&
        patch -d <SOURCE_DIR> -p1 -t -N < ${CMAKE_SOURCE_DIR}/patches/kr-origin/0001-cjk-topic-discovery.patch &&
        patch -d <SOURCE_DIR> -p1 -t -N < ${CMAKE_SOURCE_DIR}/patches/kr-origin/0002-utf8-bom-sidecars.patch &&
        patch -d <SOURCE_DIR> -p1 -t -N < ${CMAKE_SOURCE_DIR}/patches/kr-origin/0003-mixed-utf8-esm-reader.patch
)'''
if 'patches/kr-origin/0001-cjk-topic-discovery.patch' not in text:
    if needle not in text:
        raise SystemExit('official 0.51.0-09 OpenMW patch-chain tail not found')
    text = text.replace(needle, replacement, 1)
p.write_text(text, encoding='utf-8')
PY

grep -Fq "set(OPENMW_VERSION $OPENMW_COMMIT)" source/buildscripts/CMakeLists.txt
grep -Fq 'apply-android-graphics-followup4.py' source/buildscripts/CMakeLists.txt
grep -Fq 'patches/kr-origin/0003-mixed-utf8-esm-reader.patch' source/buildscripts/CMakeLists.txt

rm -rf source/buildscripts/build/arm64/openmw-prefix
set +e
(
  cd source/buildscripts
  find . -type f -name '*.sh' -exec chmod +x {} +
  set -o pipefail
  ./build.sh --arch arm64 --jobs "$JOBS" 2>&1 | tee "../../../$LOG"
)
BUILD_RC=$?
set -e

JNI='source/app/src/main/jniLibs/arm64-v8a/libopenmw.so'
SRC='source/buildscripts/build/arm64/openmw-prefix/src/openmw'
if [[ -s "$JNI" ]]; then
  cp "$JNI" "$OUTDIR/libopenmw.so"
  sha256sum "$OUTDIR/libopenmw.so" | tee "$OUTDIR/libopenmw.so.sha256"

  READELF='source/buildscripts/toolchain/ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf'
  if [[ -x "$READELF" ]]; then
    MIN_ALIGN="$($READELF -lW "$JNI" | awk '$1=="LOAD" {print $NF}' | sort -n | head -1)"
    {
      echo "upstream_tag=$UPSTREAM_TAG"
      echo "upstream_libopenmw_sha256=$OFFICIAL_SHA"
      echo "korean_libopenmw_sha256=$(sha256sum "$JNI" | awk '{print $1}')"
      echo "korean_libopenmw_min_load_align=${MIN_ALIGN:-unknown}"
    } | tee "$OUTDIR/page-size-report.txt"
  fi

  grep -Fq 'parseHyperText(text, mTranslationDataStorage, true)' "$SRC/apps/openmw/mwdialogue/dialoguemanagerimp.cpp"
  grep -Fq 'static_cast<unsigned char>(*i) < 0xe0' "$SRC/apps/openmw/mwdialogue/keywordsearch.cpp"
  grep -Fq 'utf8BomMode ? std::string_view(line)' "$SRC/components/translation/translation.cpp"
  grep -Fq 'if (isValidUtf8WithHangul(raw))' "$SRC/components/esm3/esmreader.cpp"
fi

if [[ $BUILD_RC -ne 0 ]]; then
  echo "Native build failed with exit code $BUILD_RC" >&2
  exit "$BUILD_RC"
fi

test -s "$OUTDIR/libopenmw.so"
test "$(sha256sum "$OUTDIR/libopenmw.so" | awk '{print $1}')" != "$OFFICIAL_SHA"
echo 'Korean 0.51.0-09 native runtime build completed.'
