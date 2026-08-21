<div align="center">

<img width="1541" height="333" alt="OpenMW Android" src="https://github.com/user-attachments/assets/15a5cc0d-9210-4ce6-b8a2-09304a1b72c9" />

# OpenMW Android 한국어 지원판

**The Elder Scrolls III: Morrowind를 Android에서 한국어로 플레이하기 위한 OpenMW 0.51 기반 포트**

![Android](https://img.shields.io/badge/Android-up%20to%2016-green)
![Architecture](https://img.shields.io/badge/architecture-ARM64-orange.svg)
![OpenMW](https://img.shields.io/badge/OpenMW-0.51.0--04-blue)
![Korean](https://img.shields.io/badge/Korean-KR1-6f42c1)
![Controls](https://img.shields.io/badge/Controls-Joypad%20%2F%20Touch%20%2F%20Keyboard-blueviolet)

[**최신 APK 다운로드**](https://github.com/munument1/-KR-OpenMW-Android/releases/tag/android-korean-0.51.0-04-kr1) · [**한글패치 다운로드**](https://github.com/munument1/-KR-openmw/releases/tag/openmw-0.51.0-kr1)

</div>

---

## 소개

이 저장소는 **OpenMW Android 0.51.0-04를 기반으로 한국어 플레이 환경을 통합한 Android용 빌드**입니다.

정상 동작이 확인된 Andiweli의 OpenMW-Android 0.51.0-04를 기반으로 하며, Android 런처와 설정 화면을 한국어화하고 한국어 Morrowind 데이터가 OpenMW에서 올바르게 동작하도록 필요한 엔진 처리를 추가했습니다.

이 APK에는 **Morrowind 원본 게임 데이터와 한국어 번역 데이터가 포함되어 있지 않습니다.** 원본 게임 파일과 별도의 KR1 한글패치가 필요합니다.

## KR1 주요 기능

- **OpenMW 0.51.0 Final** 기반 Android 런타임
- Android **런처와 설정 화면 한국어화**
- UTF-8 한글이 포함된 ESP/ESM 문자열 처리
- `.cel`, `.mrk`, `.top` UTF-8 BOM sidecar 처리
- 한국어/CJK 대화 토픽 탐색 지원
- `MysticCards` 폰트 슬롯을 이용한 한국어 글꼴 처리
- `Morrowind.ini`의 `[Fonts]` 항목이 한국어 폰트 설정을 덮어쓰는 문제 방지
- 게임패드, 터치, 키보드, 물리 마우스 지원
- 게임플레이, 그래픽, 그림자, 인터페이스, 엔진 설정을 Android 런처에서 직접 조절
- Original / Modified / Zesterer / OMWFX 셰이더 프리셋
- WetWorld, RainLens, Godrays, Bloom, Lens Flare 등 Android용 OMWFX 후처리 지원

## 설치에 필요한 것

1. 합법적으로 보유한 **The Elder Scrolls III: Morrowind** 게임 데이터
2. 이 저장소의 **OpenMW Android 한국어 KR1 APK**
3. [`-KR-openmw`의 KR1 한글패치](https://github.com/munument1/-KR-openmw/releases/tag/openmw-0.51.0-kr1)

Bethesda의 게임 파일은 이 저장소나 APK에 포함되어 있지 않습니다.

## 설치 방법

1. [Android KR1 릴리즈](https://github.com/munument1/-KR-OpenMW-Android/releases/tag/android-korean-0.51.0-04-kr1)에서 APK를 설치합니다.
2. Morrowind 게임 폴더를 Android 기기에 복사합니다. `Morrowind.ini`와 `Data Files` 폴더가 있는 위치를 사용하면 됩니다.
3. OpenMW Android를 실행하고 **게임 파일**에서 Morrowind 폴더를 지정합니다.
4. [`-KR-openmw` KR1 릴리즈](https://github.com/munument1/-KR-openmw/releases/tag/openmw-0.51.0-kr1)의 안내에 따라 한글패치를 적용합니다.
5. 필요한 플러그인과 리소스를 활성화한 뒤 **게임 시작**을 누릅니다.

한국어 폰트를 사용하기 위해 `user.cfg`, `openmw.cfg`, `settings.cfg`를 별도로 수정할 필요는 없습니다.

> **기존 OpenMW Android가 설치되어 있는 경우**  
> 공식 Andiweli APK나 이전 테스트 APK와 서명이 다르면 덮어쓰기가 거부될 수 있습니다. 필요한 설정과 데이터를 먼저 백업한 뒤 기존 앱을 삭제하고 설치하세요.

## APK와 한글패치의 역할

| 구성 | 역할 |
|---|---|
| **OpenMW Android 한국어 KR1 APK** | Android 런처 한국어화, 한국어 UTF-8 처리, 토픽 탐색, 폰트 슬롯 처리 등 엔진/런타임 지원 |
| **-KR-openmw KR1 한글패치** | 실제 Morrowind 한국어 번역 데이터, 플러그인, l10n 데이터, OMWFont 등 |
| **Morrowind 원본 데이터** | Bethesda의 게임 본편 및 Tribunal/Bloodmoon 데이터 |

즉 **APK만 설치해도 게임 내용이 한국어로 번역되는 것은 아닙니다.** APK와 KR1 한글패치를 함께 사용해야 합니다.

## 한국어 런타임 구현

한국어 엔진 처리는 [`munument1/-KR-openmw`](https://github.com/munument1/-KR-openmw)의 검증된 원본 패치를 기준으로 합니다.

KR1에는 다음 처리가 포함되어 있습니다.

- 한국어/CJK 대화 토픽 검색
- UTF-8 BOM이 있는 `.cel`, `.mrk`, `.top` 파일 직접 처리
- 유효한 UTF-8 한글 ESP/ESM 문자열 보존
- 기존 영문 Morrowind 마스터 파일은 기존 `win1252` 경로 유지

따라서 한국어 번역 데이터를 CP949로 다시 변환하는 방식이 아니라, **기존 OpenMW 0.51 동작을 유지하면서 한국어 데이터만 선택적으로 UTF-8로 처리**합니다.

## 검증된 KR1 빌드

| 항목 | 값 |
|---|---|
| Android 기준 버전 | `0.51.0-04` |
| OpenMW 엔진 커밋 | `f4bec41444214a7903bebd178389ca22ca13f646` |
| APK SHA-256 | `6de2bd330ce3cdbad6cb981d74ba4e6cbf914f1d3a9e7d5e5c33f3d1e491a6d9` |
| `libopenmw.so` SHA-256 | `d3ba8ac6ab2a2256000c5ebd0f446111378632503145c22a5e85d6c8be65a0b0` |
| 한국어 런타임 소스 | `munument1/-KR-openmw@aecc06a5807afacf17dccd37fb3cfc685ee580fd` |

Android 지원 라이브러리(SDL2, GL4ES, OpenAL, Collada, libc++ 등)는 정상 동작이 확인된 공식 0.51.0-04 바이너리를 유지하고, 한국어 엔진 처리가 필요한 `libopenmw.so`만 한국어 지원용으로 빌드했습니다.

## OMWFX 셰이더

이 포트는 OpenMW 후처리 프레임워크와 커뮤니티의 [OMWFX Shaders](https://gitlab.com/vtastek/omwfx-shaders)를 기반으로 한 Android용 OMWFX 프리셋을 포함합니다.

OMWFX 사용은 선택 사항이며, 기기 성능에 따라 Original 또는 다른 셰이더 프리셋을 사용할 수 있습니다.

## 프로젝트 기반 및 출처

| 구성 요소 | 출처 |
|---|---|
| Android 포트 | [Andiweli / OpenMW-Android](https://github.com/Andiweli/OpenMW-Android) |
| 기존 Android 포트 기반 | [CaveBros / openmw-android](https://gitlab.com/cavebros/openmw-android/-/releases) |
| OpenMW 엔진 | [OpenMW / openmw](https://github.com/OpenMW/openmw) |
| 한국어 런타임/한글패치 | [munument1 / -KR-openmw](https://github.com/munument1/-KR-openmw) |
| 셰이더 | [OMWFX Shaders](https://gitlab.com/vtastek/omwfx-shaders) |

## 지원 및 원작자 후원

이 저장소의 Android 기반 포트를 제작·유지해 온 Andiweli의 작업을 후원하려면 아래 PayPal 링크를 이용할 수 있습니다.

[![Support via PayPal](https://img.shields.io/badge/Support%20via-PayPal-0070BA?logo=paypal&logoColor=white)](https://paypal.me/andiweli)

## 크레딧 및 면책

OpenMW는 Morrowind 엔진을 독립적으로 재구현한 오픈 소스 프로젝트입니다. 이 Android 한국어 빌드는 **OpenMW**, **Andiweli**, **CaveBros**, **OMWFX Shaders**, 그리고 한국어 패치 작업의 결과물을 기반으로 합니다.

이 프로젝트는 Bethesda Softworks와 제휴하거나 Bethesda의 공식 승인을 받은 프로젝트가 아닙니다. **The Elder Scrolls**, **Morrowind** 및 관련 상표의 권리는 각 권리자에게 있습니다.

---

<div align="center">

**OpenMW · Morrowind · Android · 한국어 · OMWFX**

</div>
