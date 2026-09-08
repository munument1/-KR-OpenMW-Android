<div align="center">

<img width="1541" height="333" alt="image" src="https://github.com/user-attachments/assets/15a5cc0d-9210-4ce6-b8a2-09304a1b72c9" />

**향상된 조작과 OMWFX 셰이더를 제공하는 Android/ChromeOS용 OpenMW (Morrowind)**

![OS](https://img.shields.io/badge/up%20to-Android%2016-green)
![Architecture](https://img.shields.io/badge/architecture-64bit-orange.svg)
![ChromeOS](https://img.shields.io/badge/ChromeOS-Supported-4285F4?logo=googlechrome&logoColor=white)
![AI Assisted Coding](https://img.shields.io/badge/AI-Assisted%20Coding-white)
![Controller](https://img.shields.io/badge/Controls-Joypad/Touch/Keyb-blueviolet)

</div>

# OpenMW Android 및 ChromeOS 한국어 지원판

## ✨ 소개

이 프로젝트는 **The Elder Scrolls III: Morrowind를 위한 OpenMW Android/ChromeOS 포팅판**을 기반으로 한 한국어 지원 포크입니다. 원본 프로젝트는 [CaveBros openmw-android](https://gitlab.com/cavebros/openmw-android/-/releases)를 바탕으로 **OpenMW 0.51**, Android/ChromeOS 개선 사항, 향상된 포스트 프로세싱 셰이더를 추가한 [Andiweli/OpenMW-Android](https://github.com/Andiweli/OpenMW-Android)입니다.

원본 프로젝트는 수많은 OpenMW 포팅판 중 하나를 새로 만드는 것보다, CaveBros 포트의 단순하고 명확한 런처 UI를 유지하면서 더 최신 OpenMW 엔진과 현대적인 셰이더를 결합하는 데 초점을 둡니다.

목표는 upstream OpenMW 엔진과 최대한 가깝게 유지하면서 **Android 휴대기기, 태블릿 및 ChromeOS**에서 깔끔하고 컨트롤러 친화적인 Morrowind 환경을 제공하는 것입니다.

## 🇰🇷 한국어 지원판 추가 사항

현재 작업 기준은 **OpenMW Android 0.51.0-10**입니다.

- 한국어/CJK 대화 토픽 검색 보정
- UTF-8 BOM 기반 `.cel` / `.top` / `.mrk` 사이드카 지원
- UTF-8 한글이 포함된 ESM/ESP 문자열 처리 보정
- 이전 한국어 세이브의 저널 문자열 복구
- OpenMW 영상 위젯의 외부 **UTF-8 SRT 자막 지원**
- `video/<영상명>.bik` 재생 시 같은 VFS 경로의 `video/<영상명>.srt` 자동 탐색
- 본편 3개 + Bloodmoon 7개, 총 **10개 한국어 영상 자막** 지원
- Gowun Batang 기반 한국어 폰트 구성
- `Movies_New_Game=mw_intro.bik` 등 원본 Morrowind 영상 fallback 보정
- Android 15/16 대응을 위한 **16 KiB 페이지 크기 네이티브 빌드 검증**

한국어 대응 APK와 한국어 데이터 패키지는 서로 역할이 다릅니다. APK에는 한국어 문자열 처리와 SRT 표시를 위한 엔진 수정이 들어가며, 별도 한국어 데이터 패키지에는 번역 ESP/CEL/MRK/TOP/l10n, 폰트 및 SRT 자막이 포함됩니다. 원본 Bethesda 게임 데이터와 BIK 영상은 배포하지 않습니다.

## ⚔️ 주요 특징

- ⚙️ Android 포트에 **OpenMW 0.51.0 Final** 엔진 통합
- 📱 **Android 휴대기기, 태블릿, TV 기기 및 ChromeOS**에 최적화
- 🎮 향상된 **게임패드, 터치, 키보드 및 물리 마우스** 지원
- 🖥️ **게임플레이, 그래픽, 그림자, 인터페이스 및 엔진 설정**에 바로 접근할 수 있는 확장 런처
- 📐 **해상도, UI 배율, 프레임레이트 및 성능 옵션** 설정 가능
- 🌑 품질 및 거리 프리셋을 선택할 수 있는 Android 호환 **동적 그림자**
- 🎨 네 가지 셰이더 프리셋: **Original, Modified, Zesterer, OMWFX**
- ✨ **WetWorld, RainLens, Godrays, Bloom, Lens Flare**가 포함된 향상된 **OMWFX 포스트 프로세싱**
- 🧩 **모드, 사용자 데이터 파일, 셰이더 프리셋 및 환경 플래그** 지원
- 🔧 **GLES2/GL4ES, 포스트 프로세싱 및 깊이 처리**를 위한 Android 전용 수정

<img width="1920" height="1080" alt="openmw0" src="https://github.com/user-attachments/assets/993327f9-ee20-466c-b1bc-ef19c0cc1d00" />
<img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/1a742936-ebb4-4199-a565-fd7ff30a30f5" />
<img width="1920" height="1080" alt="openmw1" src="https://github.com/user-attachments/assets/ace8b873-e704-45e8-b4a5-760e4994f347" />
<img width="1920" height="1080" alt="openmw2" src="https://github.com/user-attachments/assets/97bbf06b-b6d9-4fcd-8d79-bd9f36ab7db3" />
<img width="1920" height="1080" alt="openmw4" src="https://github.com/user-attachments/assets/cb9b06d6-265c-495c-ad78-f7464ac5b541" />

## 🎨 OMWFX 셰이더

이 프로젝트에는 OpenMW 포스트 프로세싱 프레임워크와 커뮤니티의 [OMWFX Shaders 컬렉션](https://gitlab.com/vtastek/omwfx-shaders)을 기반으로 한 향상된 OMWFX 셰이더 옵션이 포함되어 있습니다.

번들 프리셋은 선택 사항으로 유지하면서 더 현대적인 화면 표현을 제공하며, 프로젝트에서 추가한 **Lens Flare** 효과도 포함합니다.

## 🧩 프로젝트 기반

| 구성 요소 | 출처 |
|---|---|
| Android 포트 | [CaveBros / openmw-android](https://gitlab.com/cavebros/openmw-android/-/releases) |
| Android/ChromeOS 기반 프로젝트 | [Andiweli / OpenMW-Android](https://github.com/Andiweli/OpenMW-Android) |
| OpenMW 엔진 | [OpenMW / openmw](https://github.com/OpenMW/openmw) |
| 셰이더 프레임워크 | [OMWFX Shaders](https://gitlab.com/vtastek/omwfx-shaders) |
| 한국어 번역/런타임 패치 | [munument1 / -KR-openmw](https://github.com/munument1/-KR-openmw) |

## 📦 준비 사항

합법적으로 보유한 **The Elder Scrolls III: Morrowind** 게임 데이터가 필요합니다. Bethesda의 게임 파일은 이 저장소나 한국어 패키지에 **포함되지 않습니다**.

한국어 데이터 패키지를 사용할 때는 OpenMW Android 런처에서 `Morrowind_Korean_ReTranslation` 폴더를 데이터 디렉터리로 추가하고 `Morrowind_Korean_ReTranslation.esp`를 활성화해야 합니다.

## ❤️ 원본 프로젝트 후원

원본 Android/ChromeOS 포트가 마음에 들고 개발을 후원하고 싶다면 원 개발자에게 PayPal로 기여할 수 있습니다.

후원은 기존 프로젝트 유지보수, 버그 수정, 호환성 개선 및 새로운 기능 개발에 도움이 됩니다.

[![Support via PayPal](https://img.shields.io/badge/Support%20via-PayPal-0070BA?logo=paypal\&logoColor=white)](https://paypal.me/andiweli)

## 📜 크레딧 및 면책

OpenMW는 Morrowind 엔진을 독립적으로 재구현한 오픈 소스 프로젝트입니다. 이 Android/ChromeOS 프로젝트는 **OpenMW**, **CaveBros**, **Andiweli/OpenMW-Android**, **OMWFX shader** 기여자들의 작업을 기반으로 합니다.

이 프로젝트는 Bethesda Softworks와 제휴하거나 공식 승인을 받은 프로젝트가 아닙니다. **The Elder Scrolls**, **Morrowind** 및 관련 상표의 권리는 각 권리자에게 있습니다.

---

<div align="center">

**OpenMW • Morrowind • Android • ChromeOS • OMWFX • 한국어 지원**

</div>
