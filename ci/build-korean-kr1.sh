#!/usr/bin/env bash
set -euo pipefail

OPENMW_COMMIT='f4bec41444214a7903bebd178389ca22ca13f646'
UPSTREAM_REPO='Andiweli/OpenMW-Android'
UPSTREAM_TAG='0.51.0-09'
UPSTREAM_APK='OpenMW.0.51-09.apk'
UPSTREAM_APK_SHA256='8acd5ae5e44c5702b449aaad8978a4e117772a655e4b119f20d860913036726e'
KOREAN_RUNTIME_REPO='munument1/-KR-OpenMW-Android'
KOREAN_RUNTIME_TAG='android-korean-0.51.0-04-kr1.1'
KOREAN_RUNTIME_APK='OpenMW-Android-0.51.0-04-Korean-KR1.1.apk'
KOREAN_RUNTIME_APK_SHA256='3a06f43652b66af257adf6f9d8f30a5fd7d2a5f61b57a60bfd80148251c208e0'
KOREAN_LIBOPENMW_SHA256='d3ba8ac6ab2a2256000c5ebd0f446111378632503145c22a5e85d6c8be65a0b0'
KOREAN_ENGINE_REPO='munument1/-KR-openmw'
KOREAN_ENGINE_COMMIT='aecc06a5807afacf17dccd37fb3cfc685ee580fd'
KOREAN_TOPIC_BLOB='4d5e8e5d72ed944fd3286615d9d50f04f2ff97b6'
KOREAN_SIDECAR_BLOB='b83eaf76d1047757214711fbd0074a03876bf6de'
KOREAN_ESM_BLOB='aa5c3e5dd74cab31aa1c17aad01a232bf057e727'

mkdir -p work/upstream work/korean-runtime work/elf source/app/src/main/jniLibs/arm64-v8a

echo 'Downloading verified APK inputs...'
gh release download "$UPSTREAM_TAG" --repo "$UPSTREAM_REPO" \
  --pattern "$UPSTREAM_APK" --dir work/upstream
gh release download "$KOREAN_RUNTIME_TAG" --repo "$KOREAN_RUNTIME_REPO" \
  --pattern "$KOREAN_RUNTIME_APK" --dir work/korean-runtime

BASE_APK="work/upstream/$UPSTREAM_APK"
KR_APK="work/korean-runtime/$KOREAN_RUNTIME_APK"
test "$(sha256sum "$BASE_APK" | awk '{print $1}')" = "$UPSTREAM_APK_SHA256"
test "$(sha256sum "$KR_APK" | awk '{print $1}')" = "$KOREAN_RUNTIME_APK_SHA256"

unzip -p "$BASE_APK" lib/arm64-v8a/libopenmw.so > work/elf/upstream-libopenmw.so
unzip -p "$KR_APK" lib/arm64-v8a/libopenmw.so > work/elf/korean-libopenmw.so
test "$(sha256sum work/elf/korean-libopenmw.so | awk '{print $1}')" = "$KOREAN_LIBOPENMW_SHA256"

elf_min_load_align() {
  python3 - "$1" <<'PY'
import subprocess, sys
path = sys.argv[1]
out = subprocess.check_output(['readelf', '-lW', path], text=True)
aligns = []
for line in out.splitlines():
    fields = line.split()
    if fields and fields[0] == 'LOAD':
        aligns.append(int(fields[-1], 0))
if not aligns:
    raise SystemExit(f'no LOAD segments found: {path}')
print(min(aligns))
PY
}

UPSTREAM_OPENMW_ALIGN="$(elf_min_load_align work/elf/upstream-libopenmw.so)"
KR_OPENMW_ALIGN="$(elf_min_load_align work/elf/korean-libopenmw.so)"
{
  echo "upstream_apk=$UPSTREAM_TAG"
  echo "upstream_apk_sha256=$UPSTREAM_APK_SHA256"
  echo "korean_runtime_source=$KOREAN_RUNTIME_TAG"
  echo "korean_runtime_apk_sha256=$KOREAN_RUNTIME_APK_SHA256"
  printf 'upstream_libopenmw_min_load_align=0x%x\n' "$UPSTREAM_OPENMW_ALIGN"
  printf 'korean_libopenmw_min_load_align=0x%x\n' "$KR_OPENMW_ALIGN"
} > page-size-report.txt

if (( KR_OPENMW_ALIGN < UPSTREAM_OPENMW_ALIGN )); then
  echo 'Korean libopenmw.so has worse ELF LOAD alignment than upstream.' >&2
  cat page-size-report.txt >&2
  exit 20
fi
if (( KR_OPENMW_ALIGN < 0x4000 )); then
  echo 'WARNING: Korean and/or upstream runtime is below 16 KiB ELF LOAD alignment.' | tee -a page-size-report.txt
fi

if readelf -S work/elf/korean-libopenmw.so 2>/dev/null | grep -Eq '\.debug_(info|line|str|abbrev)'; then
  echo 'Reused Korean libopenmw.so unexpectedly contains DWARF sections.' >&2
  exit 21
fi

NATIVE_DIR='source/app/src/main/jniLibs/arm64-v8a'
cp work/elf/korean-libopenmw.so "$NATIVE_DIR/libopenmw.so"
for library in libopenal.so libSDL2.so libGL.so libcollada-dom2.5-dp.so libc++_shared.so; do
  unzip -p "$BASE_APK" "lib/arm64-v8a/$library" > "$NATIVE_DIR/$library"
  test -s "$NATIVE_DIR/$library"
  align="$(elf_min_load_align "$NATIVE_DIR/$library")"
  printf '%s_min_load_align=0x%x\n' "$library" "$align" >> page-size-report.txt
done

# The Gradle release gate tracks the exact native payload by SHA. Point it at the
# previously device-tested Korean OpenMW 0.51 Final runtime instead of rebuilding it.
printf '%s  %s\n' "$KOREAN_LIBOPENMW_SHA256" "$NATIVE_DIR/libopenmw.so" \
  > source/buildscripts/openmw-051-patch39-libopenmw.sha256
printf '%s  %s\n' "$KOREAN_LIBOPENMW_SHA256" "$NATIVE_DIR/libopenmw.so" \
  > korean-origin-libopenmw.sha256

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

printf '%s\n' \
  "android_base=$UPSTREAM_REPO@$UPSTREAM_TAG" \
  "openmw_engine=$OPENMW_COMMIT" \
  "korean_runtime_binary=$KOREAN_RUNTIME_REPO@$KOREAN_RUNTIME_TAG" \
  "korean_runtime_apk_sha256=$KOREAN_RUNTIME_APK_SHA256" \
  "korean_libopenmw_sha256=$KOREAN_LIBOPENMW_SHA256" \
  "korean_source=$KOREAN_ENGINE_REPO@$KOREAN_ENGINE_COMMIT" \
  "topic=$KOREAN_TOPIC_BLOB" \
  "sidecar=$KOREAN_SIDECAR_BLOB" \
  "esm=$KOREAN_ESM_BLOB" > korean-origin.txt

(
  cd source
  chmod +x gradlew
  ./gradlew --no-daemon \
    :app:testMainlineDebugUnitTest --tests file.IniConverterTest \
    :app:assembleMainlineDebug
)

APK='source/app/build/outputs/apk/mainline/debug/app-mainline-debug.apk'
test -s "$APK"
test "$(unzip -p "$APK" lib/arm64-v8a/libopenmw.so | sha256sum | awk '{print $1}')" = "$KOREAN_LIBOPENMW_SHA256"
for library in libopenal.so libSDL2.so libGL.so libcollada-dom2.5-dp.so libc++_shared.so; do
  A="$(unzip -p "$APK" "lib/arm64-v8a/$library" | sha256sum | awk '{print $1}')"
  B="$(unzip -p "$BASE_APK" "lib/arm64-v8a/$library" | sha256sum | awk '{print $1}')"
  test "$A" = "$B"
done

unzip -p "$APK" assets/libopenmw/openmw/openmw.base.cfg > /tmp/openmw.base.cfg
grep -Fx 'fallback=Fonts_Font_0,MysticCards' /tmp/openmw.base.cfg
grep -Fx 'fallback=Fonts_Font_2,MysticCards' /tmp/openmw.base.cfg
"$ANDROID_HOME/build-tools/35.0.0/aapt" dump badging "$APK" > /tmp/badging.txt
grep -F "versionCode='5109'" /tmp/badging.txt
grep -F "versionName='0.51.0-09'" /tmp/badging.txt

ZIPALIGN="$ANDROID_HOME/build-tools/35.0.0/zipalign"
if "$ZIPALIGN" -c -P 16 4 "$BASE_APK" >/dev/null 2>&1; then
  echo 'upstream_apk_zipalign_16k=pass' >> page-size-report.txt
  if ! "$ZIPALIGN" -c -P 16 4 "$APK" >/dev/null 2>&1; then
    echo 'built_apk_zipalign_16k=fail' >> page-size-report.txt
    echo 'Built APK regressed 16 KiB ZIP alignment relative to upstream.' >&2
    exit 22
  fi
  echo 'built_apk_zipalign_16k=pass' >> page-size-report.txt
else
  echo 'upstream_apk_zipalign_16k=fail' >> page-size-report.txt
  if "$ZIPALIGN" -c -P 16 4 "$APK" >/dev/null 2>&1; then
    echo 'built_apk_zipalign_16k=pass' >> page-size-report.txt
  else
    echo 'built_apk_zipalign_16k=fail' >> page-size-report.txt
  fi
fi

OUT='source/app/build/outputs/apk/mainline/debug/OpenMW-Android-0.51.0-09-Korean-KR1.apk'
cp "$APK" "$OUT"
sha256sum "$OUT" | tee "$OUT.sha256"
cat page-size-report.txt
