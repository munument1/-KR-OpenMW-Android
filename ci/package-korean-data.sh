#!/usr/bin/env bash
set -euo pipefail

# Build an Android-ready Korean data directory from the exact Windows KR3
# translation payload that has already been tested with OpenMW 0.51.0.
# Only Korean data/fonts/subtitles are reused; Windows executables and installer
# files are never copied into the Android package.
KOREAN_REPO='munument1/-KR-openmw'
KOREAN_TAG='openmw-0.51.0-kr3'
KOREAN_ASSET='Morrowind-Korean-OpenMW-0.51.0-KR3-Full.zip'
KOREAN_ASSET_SHA256='b678745854ae6787ba9c317802639f78853f5e786b7d773d05a5d4a02b622751'

WORK='work/korean-data'
SOURCE_DIR="$WORK/source"
STAGING_DIR="$WORK/staging"
DATA_DIR="$STAGING_DIR/Morrowind_Korean_ReTranslation"
OUTDIR='release-artifacts'
OUT="$OUTDIR/OpenMW-Android-0.51.0-10-Korean-Data-KR3.zip"

rm -rf "$WORK"
mkdir -p "$SOURCE_DIR" "$DATA_DIR/Fonts" "$OUTDIR"

gh release download "$KOREAN_TAG" \
  --repo "$KOREAN_REPO" \
  --pattern "$KOREAN_ASSET" \
  --dir "$SOURCE_DIR" \
  --clobber

SOURCE_ZIP="$SOURCE_DIR/$KOREAN_ASSET"
test -s "$SOURCE_ZIP"
test "$(sha256sum "$SOURCE_ZIP" | awk '{print $1}')" = "$KOREAN_ASSET_SHA256"

unzip -q "$SOURCE_ZIP" \
  'payload/mods/Morrowind_Korean_ReTranslation/*' \
  'payload/resources/vfs/fonts/MysticCards.omwfont' \
  'payload/resources/vfs/fonts/GowunBatang-Bold.ttf' \
  'payload/resources/vfs/fonts/GowunBatang-OFL.txt' \
  -d "$SOURCE_DIR/extracted"

cp -a "$SOURCE_DIR/extracted/payload/mods/Morrowind_Korean_ReTranslation/." "$DATA_DIR/"
cp "$SOURCE_DIR/extracted/payload/resources/vfs/fonts/MysticCards.omwfont" "$DATA_DIR/Fonts/"
cp "$SOURCE_DIR/extracted/payload/resources/vfs/fonts/GowunBatang-Bold.ttf" "$DATA_DIR/Fonts/"
cp "$SOURCE_DIR/extracted/payload/resources/vfs/fonts/GowunBatang-OFL.txt" "$DATA_DIR/Fonts/"

# Core Korean data must all be present.
for required in \
  Morrowind_Korean_ReTranslation.esp \
  Morrowind_Korean_ReTranslation.cel \
  Morrowind_Korean_ReTranslation.mrk \
  Morrowind_Korean_ReTranslation.top \
  Fonts/MysticCards.omwfont \
  Fonts/GowunBatang-Bold.ttf; do
  test -s "$DATA_DIR/$required"
done

test -d "$DATA_DIR/l10n"

# The Android runtime patch maps video/foo.bik -> video/foo.srt through VFS.
# Keep the exact ten subtitle tracks that were validated on the Windows KR3
# runtime. Original BIK files are neither modified nor redistributed.
SUBTITLES=(
  mw_intro
  mw_cavern
  mw_end
  bm_bearhunt1
  bm_bearhunt2
  bm_ceremony1
  bm_ceremony2
  bm_endgame
  bm_frostgiant1
  bm_frostgiant2
)

for subtitle in "${SUBTITLES[@]}"; do
  test -s "$DATA_DIR/video/$subtitle.srt"
done

test "$(find "$DATA_DIR/video" -maxdepth 1 -type f -name '*.srt' | wc -l)" -eq 10

grep -Fq 'GowunBatang-Bold.ttf' "$DATA_DIR/Fonts/MysticCards.omwfont"

cat > "$STAGING_DIR/README-ANDROID-KO.txt" <<'EOF'
OpenMW Android 0.51.0-10 한국어 데이터 패키지

이 압축 파일은 한국어 번역 데이터, Gowun Batang 기반 MysticCards 폰트,
그리고 본편 3개 + Bloodmoon 7개 영상용 한국어 SRT 자막을 포함합니다.
원본 Morrowind BIK 영상과 Bethesda 게임 데이터는 포함하지 않습니다.

설치
1. Morrowind_Korean_ReTranslation 폴더를 Android 기기에 복사합니다.
2. OpenMW Android 런처의 모드 > 디렉터리에서 이 폴더를 데이터 디렉터리로 추가합니다.
3. 모드 > 플러그인에서 Morrowind_Korean_ReTranslation.esp를 활성화합니다.
4. 한국어 대응 APK로 게임을 실행합니다.

한국어 대응 APK는 video/<영상명>.bik 재생 시 같은 VFS 경로의
video/<영상명>.srt를 자동으로 찾아 표시합니다.
EOF

rm -f "$OUT" "$OUT.sha256"
(
  cd "$STAGING_DIR"
  zip -qr "$(realpath --relative-to="$STAGING_DIR" "$OUT")" .
)

test -s "$OUT"
unzip -tq "$OUT"
sha256sum "$OUT" | tee "$OUT.sha256"

{
  echo 'OpenMW Android 0.51.0-10 Korean data package'
  echo 'source_repo=munument1/-KR-openmw'
  echo "source_tag=$KOREAN_TAG"
  echo "source_asset=$KOREAN_ASSET"
  echo "source_asset_sha256=$KOREAN_ASSET_SHA256"
  echo 'subtitle_count=10'
  echo 'font=MysticCards.omwfont -> GowunBatang-Bold.ttf'
  echo 'result=PASS'
} > "$OUTDIR/korean-data-verification.txt"

echo 'Android Korean data package with 10 video subtitles verified.'
