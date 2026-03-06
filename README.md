<p align="center">
  <img src="assets/icon.png" width="120" height="120" alt="냥냥 일본어 로고">
</p>

# 🌸 냥냥 일본어 (Nyang Nyang Japanese) - JLPT 단어장

**냥냥 일본어**는 JLPT(일본어 능력 시험) 합격을 목표로 하는 초보자부터 상급자까지, N1부터 N5까지의 필수 단어를 쉽고 체계적으로 암기할 수 있도록 도와주는 감성적인 Flutter 기반 어플리케이션입니다.

---

## ✨ 최근 업데이트: 아키텍처 고도화 및 성능 혁신 (Architecture 2.0)

대규모 리팩토링을 통해 앱의 안정성과 속도를 비약적으로 향상시켰습니다.

### 1. 🚀 로컬 퍼스트(Local-First) 최적화 및 랙(Jank) 해결
*   **비동기 업로드(Fire & Forget)**: 퀴즈 풀이 및 북마크 시 발생하는 실시간 서버 통신을 `await` 없이 백그라운드로 전환하여, 네트워크 상태에 관계없이 **0ms의 즉각적인 UI 반응성**을 구현했습니다.
*   **배치 동기화**: 수백 번의 개별 요청 대신 퀴즈 종료 시점에 데이터를 한꺼번에 전송하여 배터리와 데이터 소모를 획기적으로 줄였습니다.
*   **부팅 지연 전략**: 앱 시작 시 발생하는 과부하를 방지하기 위해 서버 버전 체크 및 동기화 작업을 부팅 3초 후로 미루어 사용자가 홈 화면에 진입하는 속도를 최적화했습니다.

### 2. 🏗️ 고도화된 데이터 아키텍처 (Database 2.0)
*   **사전과 기록의 분리**: 공용 단어 데이터(`words_master`)와 사용자 개인 학습 기록(`user_progress`)을 물리적으로 분리하여 데이터 무결성을 확보했습니다.
*   **양방향 지능형 병합(Merge)**: 기기 데이터와 클라우드 데이터 충돌 시, 학습량이 더 많은 기록을 우선적으로 보존하고 상태를 통합하는 병합 알고리즘을 적용했습니다.
*   **사용자 주도 동기화**: 구글 로그인 시 사용자가 직접 "기기 데이터 업로드" 또는 "클라우드 데이터 다운로드"를 선택할 수 있는 예쁜 커스텀 다이얼로그를 제공합니다.

### 3. 🛡️ 철벽 보안 정책 (RLS 2.0)
*   **auth_id 기반 검증**: 앱 고유 ID(`sid`)와 Supabase의 실제 로그인 UID(`auth_id`)를 이중 대조하여 본인의 데이터만 접근할 수 있도록 Row Level Security 정책을 강화했습니다.
*   **관리자 전용 단어 관리**: 관리자(`is_admin`) 권한이 부여된 계정만 서버의 마스터 단어장을 갱신할 수 있도록 보안 허들을 높였습니다.

---

## 📅 오늘(2026-03-06)의 주요 개선 사항

데이터 정합성과 사용자 경험을 극대화하기 위한 정밀 튜닝이 진행되었습니다.

### 1. 🗳️ 동기화 주권(Data Sovereignty) 확보
*   **덮어쓰기 방어**: 구글 연동 시 사용자의 명시적인 선택(업로드/다운로드) 전까지 서버 데이터가 로컬 설정을 침범하지 못하도록 로직을 분리했습니다.
*   **설정 즉시 보고**: 다크모드 스위치나 테마 변경 시, 페이지를 나갈 때까지 기다리지 않고 변경 즉시 백그라운드에서 서버로 동기화하여 데이터 유실을 0%로 낮췄습니다.
*   **닉네임/테마 보존**: "기기 데이터 유지" 선택 시 현재 설정된 감성 테마와 닉네임이 클라우드 설정을 압도하고 주 데이터로 승격됩니다.

### 2. 🎨 사용자 중심 UX 및 UI 정교화
*   **스마트 통계 지표**: '복습 필요 단어'의 기준을 직관적인 '오답노트 개수'로 변경하여 학습 목표를 명확히 했습니다.
*   **주의 환기용 컬러 적용**: '실력 진단 초기화' 등 민감한 버튼에 경고의 의미를 담은 주황색(Amber) 테마를 적용했습니다.
*   **고정형 테마 메뉴**: `PopupMenuButton`을 도입하여 테마 선택 메뉴가 항상 '자동'부터 순서대로 고정되어 나타나도록 레이아웃 안정성을 확보했습니다.

### 3. 🛠️ 결함 없는 초기화 및 동기화
*   **전수조사 초기화**: 공장 초기화 시 DB의 모든 인덱스를 낱낱이 뒤져 단 한 개의 잔상(0.1%의 오차)도 남지 않는 완벽한 데이터 클리닝을 구현했습니다.
*   **로그 한글화**: 시스템 내부의 모든 디버그 메시지를 친절한 한글로 전환하여 개발 및 운영 가독성을 높였습니다.

---

## 📱 주요 기능

- **레벨별 단어 학습**: JLPT N1 ~ N5 단계별 필수 단어 제공
- **에빙하우스 복습 시스템 (SRS)**: 망각 곡선을 기반으로 최적화된 7단계 복습 알고리즘 적용
- **오늘의 단어**: 사용자의 학습 수준에 맞춘 매일 10개씩의 맞춤형 세션
- **히라가나/가타카나 학습**: 행 단위 집중 퀴즈 및 붓글씨 모드 따라 쓰기 연습장
- **학습 통계 & 캘린더**: 나의 진도율과 학습 습관을 시각적으로 확인

---

## 📸 Screenshots

| 메인 화면 | 단어 리스트 | 퀴즈 화면 |
| :---: | :---: | :---: |
| <img src="screenshots/home.png" width="200"> | <img src="screenshots/list.png" width="200"> | <img src="screenshots/quiz.png" width="200"> |

| 오답노트 | 실력 테스트 | 따라 쓰기 |
| :---: | :---: | :---: |
| <img src="screenshots/wrong.png" width="200"> | <img src="screenshots/test.png" width="200"> | <img src="screenshots/draw.png" width="200"> |

---

## 🛠 Tech Stack

- **Framework**: [Flutter](https://flutter.dev/) (Material 3)
- **Language**: [Dart](https://dart.dev/)
- **Database**: 
  - [Hive](https://pub.dev/packages/hive) (Local NoSQL for Offline First)
  - [Supabase PostgREST](https://supabase.com/) (Cloud Storage & Advanced RLS)
- **Authentication**: Google Sign-In & Supabase Auth (UID Link)
- **State Management**: [Provider](https://pub.dev/packages/provider)
- **Localization**: `Intl` (ko_KR)

---

## 🚀 시작하기

1. 저장소 클론: `git clone https://github.com/your-username/my_voca_japan_app.git`
2. 패키지 설치: `flutter pub get`
3. Hive 어댑터 생성: `dart run build_runner build --delete-conflicting-outputs`
4. 앱 실행: `flutter run`

---
*JLPT 합격을 응원합니다! 냥냥 일본어와 함께 즐겁게 공부하세요! 🐾 🇯🇵*
