<div align="center">

<img width="1541" height="333" alt="OpenMW Android" src="https://github.com/user-attachments/assets/15a5cc0d-9210-4ce6-b8a2-09304a1b72c9" />

# OpenMW Android 한국어 지원판

**The Elder Scrolls III: Morrowind를 Android에서 한국어로 플레이하기 위한 OpenMW 0.51 기반 포트**

![Android](https://img.shields.io/badge/Android-up%20to%2016-green)
![Architecture](https://img.shields.io/badge/architecture-ARM64-orange.svg)
![OpenMW](https://img.shields.io/badge/OpenMW-0.51.0--04-blue)
![Korean](https://img.shields.io/badge/Korean-KR1-6f42c1)
![Controls](https://img.shields.io/badge/Controls-Joypad%20%2F%20Touch%20%2F%20Keyboard-blueviolet)

[**KR1 다운로드 — APK + 한글패치**](https://github.com/munument1/-KR-OpenMW-Android/releases/tag/android-korean-0.51.0-04-kr1)

</div>

---

## 소개

이 저장소는 **OpenMW Android 0.51.0-04를 기반으로 한국어 플레이 환경을 정리한 Android용 포트**입니다.

정상 동작이 확인된 Andiweli의 OpenMW-Android 0.51.0-04를 기반으로 하며, Android 런처와 설정 화면을 한국어화하고 Morrowind 한국어 번역 데이터가 OpenMW에서 올바르게 동작하도록 필요한 엔진 처리를 추가했습니다.

**KR1 릴리즈에는 Android APK와 한글패치가 함께 제공됩니다.** 별도의 저장소를 찾아다닐 필요 없이 이 저장소의 Release 페이지에서 필요한 배포 파일을 받을 수 있습니다.

단, **Bethesda의 Morrowind 원본 게임 데이터는 포함되어 있지 않습니다.** 게임을 플레이하려면 합법적으로 보유한 Morrowind 데이터가 필요합니다.

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

## 다운로드

릴리즈에서 다음 두 종류의 파일을 받으면 됩니다.

- **OpenMW Android 한국어 KR1 APK** — Android 앱 및 한국어 대응 엔진
- **KR1 한글패치 압축 파일** — 실제 Morrowind 한국어 번역 데이터, 플러그인, l10n 데이터, OMWFont 등

> APK 안에 Bethesda 게임 데이터나 한글 번역 데이터가 합쳐져 있는 것은 아닙니다.  
> **APK와 한글패치는 같은 릴리즈에서 함께 배포하지만 서로 별도 파일입니다.**

## 설치에 필요한 것

1. 합법적으로 보유한 **The Elder Scrolls III: Morrowind** 게임 데이터
2. KR1 릴리즈에 첨부된 **OpenMW Android 한국어 APK**
3. 같은 KR1 릴리즈에 첨부된 **한글패치 압축 파일**

Tribunal과 Bloodmoon을 사용하는 경우 해당 확장팩 원본 데이터도 필요합니다.

## 설치 방법

1. [KR1 릴리즈](https://github.com/munument1/-KR-OpenMW-Android/releases/tag/android-korean-0.51.0-04-kr1)에서 **APK와 한글패치 파일을 모두 다운로드**합니다.
2. APK를 Android 기기에 설치합니다.
3. PC의 Morrowind 게임 폴더를 Android 기기에 복사합니다. `Morrowind.ini`와 `Data Files` 폴더가 들어 있는 게임 폴더를 사용하면 됩니다.
4. OpenMW Android를 실행하고 **게임 파일**에서 Morrowind 폴더를 지정합니다.
5. 같은 릴리즈에 포함된 한글패치를 적용합니다.
6. 한글패치의 플러그인과 리소스를 활성화합니다.
7. **게임 시작**을 눌러 실행합니다.

한국어 폰트를 사용하기 위해 `user.cfg`, `openmw.cfg`, `settings.cfg`를 별도로 수정할 필요는 없습니다.

> **기존 OpenMW Android가 설치되어 있는 경우**  
> 공식 Andiweli APK나 이전 테스트 APK와 서명이 다르면 덮어쓰기가 거부될 수 있습니다. 필요한 설정과 데이터를 백업한 뒤 기존 앱을 삭제하고 설치하세요.

## 구성과 역할

| 구성 | 역할 |
|---|---|
| **OpenMW Android 한국어 KR1 APK** | Android 런처 한국어화, 한국어 UTF-8 처리, 대화 토픽 탐색, 폰트 슬롯 처리 등 엔진/런타임 지원 |
| **KR1 한글패치** | 실제 Morrowind 한국어 번역 데이터, 플러그인, l10n 데이터, OMWFont 등 |
| **Morrowind 원본 데이터** | Bethesda의 게임 본편 및 Tribunal/Bloodmoon 원본 데이터 |

세 구성 요소의 역할은 서로 다릅니다. **게임 원본 데이터 + 한국어 APK + 한글패치**가 함께 있어야 한국어 플레이 환경이 완성됩니다.

## 한국어 런타임 구현

한국어 엔진 처리는 [`munument1/-KR-openmw`](https://github.com/munument1/-KR-openmw)의 검증된 원본 패치를 기준으로 합니다.

KR1에는 다음 처리가 포함되어 있습니다.

- 한국어/CJK 대화 토픽 검색
- UTF-8 BOM이 있는 `.cel`, `.mrk`, `.top` 파일 직접 처리
- 유효한 UTF-8 한글 ESP/ESM 문자열 보존
- 기존 영문 Morrowind 마스터 파일은 기존 `win1252` 경로 유지

한국어 번역 데이터를 CP949로 다시 변환하는 방식이 아니라, **기존 OpenMW 0.51 동작을 유지하면서 한국어 데이터만 선택적으로 UTF-8로 처리**합니다.

## 실게임 확인 항목

KR1 개발 과정에서 다음과 같은 한국어 플레이 경로를 확인했습니다.

- 한국어 런처 및 게임 설정 화면
- NPC, 아이템, 대화, 책, 일지 표시
- CELL 및 지역명 표시
- 저장 및 불러오기
- Tribunal / Bloodmoon 기본 동작 확인
- 하스팟 안타볼리스 관련 대화 진행
- 라니스 아트리스 마법사 길드 가입 및 임무 진행
- 아지라 / 갈베디르 내기 관련 대화 진행

## 검증된 KR1 APK

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

OMWFX 사용은 선택 사항입니다. 기기 성능이나 취향에 따라 Original, Modified, Zesterer 또는 OMWFX 프리셋을 사용할 수 있습니다.

## 프로젝트 기반 및 출처

| 구성 요소 | 출처 |
|---|---|
| Android 포트 | [Andiweli / OpenMW-Android](https://github.com/Andiweli/OpenMW-Android) |
| 기존 Android 포트 기반 | [CaveBros / openmw-android](https://gitlab.com/cavebros/openmw-android/-/releases) |
| OpenMW 엔진 | [OpenMW / openmw](https://github.com/OpenMW/openmw) |
| 한국어 런타임 및 번역 원본 | [munument1 / -KR-openmw](https://github.com/munument1/-KR-openmw) |
| 셰이더 | [OMWFX Shaders](https://gitlab.com/vtastek/omwfx-shaders) |

`-KR-openmw` 저장소는 한국어 런타임 패치의 원본 소스와 개발/검증 이력을 보존하는 저장소입니다. 일반 사용자는 이 Android 저장소의 KR1 Release에서 필요한 배포 파일을 받을 수 있습니다.

## 지원 및 원작자 후원

이 저장소의 기반이 된 Android 포트를 제작·유지해 온 Andiweli의 작업을 후원하려면 아래 PayPal 링크를 이용할 수 있습니다.

[![Support via PayPal](https://img.shields.io/badge/Support%20via-PayPal-0070BA?logo=paypal&logoColor=white)](https://paypal.me/andiweli)

## 크레딧 및 면책

OpenMW는 Morrowind 엔진을 독립적으로 재구현한 오픈 소스 프로젝트입니다. 이 Android 한국어 빌드는 **OpenMW**, **Andiweli**, **CaveBros**, **OMWFX Shaders**, 그리고 한국어 패치 작업의 결과물을 기반으로 합니다.

이 프로젝트는 Bethesda Softworks와 제휴하거나 Bethesda의 공식 승인을 받은 프로젝트가 아닙니다. **The Elder Scrolls**, **Morrowind** 및 관련 상표의 권리는 각 권리자에게 있습니다.

---

<div align="center">

**OpenMW · Morrowind · Android · 한국어 · OMWFX**

</div>
