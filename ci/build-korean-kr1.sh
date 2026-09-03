#!/usr/bin/env bash
set -euo pipefail

OPENMW_COMMIT='f4bec41444214a7903bebd178389ca22ca13f646'
UPSTREAM_REPO='Andiweli/OpenMW-Android'
UPSTREAM_TAG='0.51.0-04'
UPSTREAM_APK='OpenMW.0.51-4.apk'
UPSTREAM_APK_SHA256='93da9dc4a15fed578631b22c86fc43c187b47dbcec68dc4d324cb3e31b47a007'
OFFICIAL_LIBOPENMW_SHA256='a99f89d2e8de0f652de219af9acd29db48db10f55f0026cc7a911c426a7efdc0'
KOREAN_ENGINE_REPO='munument1/-KR-openmw'
KOREAN_ENGINE_COMMIT='aecc06a5807afacf17dccd37fb3cfc685ee580fd'
KOREAN_TOPIC_BLOB='4d5e8e5d72ed944fd3286615d9d50f04f2ff97b6'
KOREAN_SIDECAR_BLOB='b83eaf76d1047757214711fbd0074a03876bf6de'
KOREAN_ESM_BLOB='aa5c3e5dd74cab31aa1c17aad01a232bf057e727'
JOBS="${JOBS:-2}"

DEST='source/buildscripts/patches/kr-origin'
rm -rf "$DEST"
mkdir -p "$DEST" work/upstream

fetch_patch() {
  local src="$1"
  local dst="$2"
  local expected="$3"
  gh api "repos/$KOREAN_ENGINE_REPO/contents/$src?ref=$KOREAN_ENGINE_COMMIT" --jq '.content' \
    | base64 --decode > "$dst"
  test -s "$dst"
  local actual
  actual="$(git hash-object "$dst")"
  echo "$src blob=$actual"
  test "$actual" = "$expected"
}

fetch_patch 'korean/patches/0001-cjk-topic-discovery.patch' \
  "$DEST/0001-cjk-topic-discovery.patch" "$KOREAN_TOPIC_BLOB"
fetch_patch 'korean/patches/0002-utf8-bom-sidecars.patch' \
  "$DEST/0002-utf8-bom-sidecars.patch" "$KOREAN_SIDECAR_BLOB"
fetch_patch 'korean/patches/0003-mixed-utf8-esm-reader.patch' \
  "$DEST/0003-mixed-utf8-esm-reader.patch" "$KOREAN_ESM_BLOB"

printf '%s\n' \
  "$KOREAN_ENGINE_REPO@$KOREAN_ENGINE_COMMIT" \
  "topic=$KOREAN_TOPIC_BLOB" \
  "sidecar=$KOREAN_SIDECAR_BLOB" \
  "esm=$KOREAN_ESM_BLOB" > korean-origin.txt

gh release download "$UPSTREAM_TAG" --repo "$UPSTREAM_REPO" \
  --pattern "$UPSTREAM_APK" --dir work/upstream
BASE_APK="work/upstream/$UPSTREAM_APK"
test "$(sha256sum "$BASE_APK" | awk '{print $1}')" = "$UPSTREAM_APK_SHA256"
test "$(unzip -p "$BASE_APK" lib/arm64-v8a/libopenmw.so | sha256sum | awk '{print $1}')" = "$OFFICIAL_LIBOPENMW_SHA256"

python3 - <<'PY'
from pathlib import Path
p = Path('source/buildscripts/CMakeLists.txt')
text = p.read_text(encoding='utf-8')
old = '        python3 ${CMAKE_SOURCE_DIR}/patches/openmw051-final/apply-android-graphics-followup4.py <SOURCE_DIR>\n)'
new = '''        python3 ${CMAKE_SOURCE_DIR}/patches/openmw051-final/apply-android-graphics-followup4.py <SOURCE_DIR> &&
        patch -d <SOURCE_DIR> -p1 -t -N < ${CMAKE_SOURCE_DIR}/patches/kr-origin/0001-cjk-topic-discovery.patch &&
        patch -d <SOURCE_DIR> -p1 -t -N < ${CMAKE_SOURCE_DIR}/patches/kr-origin/0002-utf8-bom-sidecars.patch &&
        patch -d <SOURCE_DIR> -p1 -t -N < ${CMAKE_SOURCE_DIR}/patches/kr-origin/0003-mixed-utf8-esm-reader.patch
)'''
if old not in text:
    raise SystemExit('official Android OpenMW patch-chain tail not found')
p.write_text(text.replace(old, new, 1), encoding='utf-8')
PY

grep -Fq "set(OPENMW_VERSION $OPENMW_COMMIT)" source/buildscripts/CMakeLists.txt
grep -Fq 'patches/kr-origin/0001-cjk-topic-discovery.patch' source/buildscripts/CMakeLists.txt
grep -Fq 'patches/kr-origin/0002-utf8-bom-sidecars.patch' source/buildscripts/CMakeLists.txt
grep -Fq 'patches/kr-origin/0003-mixed-utf8-esm-reader.patch' source/buildscripts/CMakeLists.txt

rm -rf source/buildscripts/build/arm64/openmw-prefix
(
  cd source/buildscripts
  find . -type f -name '*.sh' -exec chmod +x {} +
  set -o pipefail
  ./build.sh --arch arm64 --jobs "$JOBS" 2>&1 | tee korean-origin-native-build.log
)

SRC='source/buildscripts/build/arm64/openmw-prefix/src/openmw'
JNI='source/app/src/main/jniLibs/arm64-v8a/libopenmw.so'
test -s "$JNI"
grep -Fq 'parseHyperText(text, mTranslationDataStorage, true)' "$SRC/apps/openmw/mwdialogue/dialoguemanagerimp.cpp"
grep -Fq 'static_cast<unsigned char>(*i) < 0xe0' "$SRC/apps/openmw/mwdialogue/keywordsearch.cpp"
grep -Fq 'utf8BomMode ? std::string_view(line)' "$SRC/components/translation/translation.cpp"
grep -Fq 'if (isValidUtf8WithHangul(raw))' "$SRC/components/esm3/esmreader.cpp"

READELF='source/buildscripts/toolchain/ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf'
test -x "$READELF"
if "$READELF" -S "$JNI" 2>/dev/null | grep -Eq '\.debug_(info|line|str|abbrev)'; then
  echo 'Packaged Korean libopenmw.so contains DWARF sections.' >&2
  exit 1
fi

NEW_SHA="$(sha256sum "$JNI" | awk '{print $1}')"
test "$NEW_SHA" != "$OFFICIAL_LIBOPENMW_SHA256"
printf '%s  %s\n' "$NEW_SHA" "$JNI" > korean-origin-libopenmw.sha256

NATIVE_DIR='source/app/src/main/jniLibs/arm64-v8a'
mkdir -p "$NATIVE_DIR"
for library in libopenal.so libSDL2.so libGL.so libcollada-dom2.5-dp.so libc++_shared.so; do
  unzip -p "$BASE_APK" "lib/arm64-v8a/$library" > "$NATIVE_DIR/$library"
  test -s "$NATIVE_DIR/$library"
done

EXTRACTED='work/upstream/resources'
rm -rf "$EXTRACTED" source/app/src/main/assets/libopenmw source/app/src/main/assets/android_omwfx
mkdir -p "$EXTRACTED" source/app/src/main/assets
unzip -q "$BASE_APK" 'assets/libopenmw/*' 'assets/android_omwfx/*' -d "$EXTRACTED"
cp -a "$EXTRACTED/assets/libopenmw" source/app/src/main/assets/
cp -a "$EXTRACTED/assets/android_omwfx" source/app/src/main/assets/
test "$(cat source/app/src/main/assets/libopenmw/openmw/openmw-engine-version.txt)" = \
  $'OpenMW 0.51.0 Final\ncommit=f4bec41444214a7903bebd178389ca22ca13f646'

python3 - <<'PY'
from pathlib import Path
p = Path('source/app/src/main/assets/libopenmw/openmw/openmw.base.cfg')
text = p.read_text(encoding='utf-8').replace('\r\n', '\n')
lines = [line for line in text.splitlines()
         if not line.startswith('fallback=Fonts_Font_0,')
         and not line.startswith('fallback=Fonts_Font_2,')]
lines += ['fallback=Fonts_Font_0,MysticCards', 'fallback=Fonts_Font_2,MysticCards']
p.write_text('\n'.join(lines) + '\n', encoding='utf-8')
PY

grep -Fx 'fallback=Fonts_Font_0,MysticCards' source/app/openmw.base.cfg
grep -Fx 'fallback=Fonts_Font_2,MysticCards' source/app/openmw.base.cfg
grep -Fx 'fallback=Fonts_Font_0,MysticCards' source/app/src/main/assets/libopenmw/openmw/openmw.base.cfg
grep -Fx 'fallback=Fonts_Font_2,MysticCards' source/app/src/main/assets/libopenmw/openmw/openmw.base.cfg
grep -Fq 'category.equals("Fonts", ignoreCase = true)' source/app/src/main/java/file/IniConverter.kt

(
  cd source
  chmod +x gradlew
  ./gradlew --no-daemon :app:testMainlineDebugUnitTest --tests file.IniConverterTest
  ./gradlew --no-daemon :app:assembleMainlineDebug
)

APK='source/app/build/outputs/apk/mainline/debug/app-mainline-debug.apk'
test -s "$APK"
test "$(unzip -p "$APK" lib/arm64-v8a/libopenmw.so | sha256sum | awk '{print $1}')" = "$NEW_SHA"
for library in libopenal.so libSDL2.so libGL.so libcollada-dom2.5-dp.so libc++_shared.so; do
  A="$(unzip -p "$APK" "lib/arm64-v8a/$library" | sha256sum | awk '{print $1}')"
  B="$(unzip -p "$BASE_APK" "lib/arm64-v8a/$library" | sha256sum | awk '{print $1}')"
  test "$A" = "$B"
done

unzip -p "$APK" assets/libopenmw/openmw/openmw.base.cfg > /tmp/openmw.base.cfg
grep -Fx 'fallback=Fonts_Font_0,MysticCards' /tmp/openmw.base.cfg
grep -Fx 'fallback=Fonts_Font_2,MysticCards' /tmp/openmw.base.cfg
"$ANDROID_HOME/build-tools/35.0.0/aapt" dump badging "$APK" > /tmp/badging.txt
grep -F "versionCode='5104'" /tmp/badging.txt
grep -F "versionName='0.51.0-04'" /tmp/badging.txt

OUT='source/app/build/outputs/apk/mainline/debug/OpenMW-Android-0.51.0-04-Korean-KR1.apk'
cp "$APK" "$OUT"
sha256sum "$OUT" | tee "$OUT.sha256"
