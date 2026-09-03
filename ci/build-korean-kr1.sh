#!/usr/bin/env bash
set -euo pipefail

# Fail closed until a Korean libopenmw.so built against the OpenMW-Android
# 0.51.0-09 native patch chain has been produced and pinned.
#
# IMPORTANT:
# 0.51.0-09 keeps the same upstream OpenMW commit as 0.51.0-04, but its
# Android native patch chain is NOT identical. 0.51.0-09 adds the
# apply-android-graphics-followup*.py patches after the old 0.51.0-04 tail.
# Reusing the device-tested 0.51.0-04 Korean libopenmw.so therefore drops
# native fixes from the 0.51.0-09 Android runtime and is not release-safe.

OLD_KR_LIBOPENMW_SHA256='d3ba8ac6ab2a2256000c5ebd0f446111378632503145c22a5e85d6c8be65a0b0'
PIN_FILE='ci/openmw-0.51.0-09-korean-libopenmw.sha256'

cat >&2 <<EOF
Korean Android 0.51.0-09 native runtime is not pinned yet.
Refusing to reuse the 0.51.0-04 Korean libopenmw.so:
  $OLD_KR_LIBOPENMW_SHA256

The successful lightweight Run #5 / artifact 9917385717 is INVALID FOR RELEASE.
Build a fresh 0.51.0-09 Korean native runtime with:
  ci/build-korean-native-kr1.sh
Then pin and verify that new runtime before restoring the fast APK assembly path.
Expected pin file:
  $PIN_FILE
EOF

exit 23
