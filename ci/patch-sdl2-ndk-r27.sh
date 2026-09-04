#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
p = Path('source/buildscripts/CMakeLists.txt')
text = p.read_text(encoding='utf-8')
old = '''ExternalProject_Add(sdl2
        URL https://www.libsdl.org/release/SDL2-${SDL2_VERSION}.tar.gz
        URL_HASH ${SDL2_HASH}
        DOWNLOAD_DIR ${download_dir}


        CONFIGURE_COMMAND ""

        BUILD_COMMAND ${wrapper_command} ndk-build'''
new = '''ExternalProject_Add(sdl2
        URL https://www.libsdl.org/release/SDL2-${SDL2_VERSION}.tar.gz
        URL_HASH ${SDL2_HASH}
        DOWNLOAD_DIR ${download_dir}

        # NDK r27 removed ALooper_pollAll from the headers. SDL 2.0.22 still
        # calls it in the Android sensor backend; ALooper_pollOnce is the safe
        # replacement used by newer SDL revisions.
        PATCH_COMMAND sed -i s/ALooper_pollAll/ALooper_pollOnce/g <SOURCE_DIR>/src/sensor/android/SDL_androidsensor.c

        CONFIGURE_COMMAND ""

        BUILD_COMMAND ${wrapper_command} ndk-build'''
if new not in text:
    if old not in text:
        raise SystemExit('SDL2 ExternalProject anchor not found')
    text = text.replace(old, new, 1)
p.write_text(text, encoding='utf-8')
PY

grep -Fq 'ALooper_pollOnce/g' source/buildscripts/CMakeLists.txt
