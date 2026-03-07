<p align="center">
  <img src="assets/icon.png" width="120" height="120" alt="냥냥 일본어 로고">
</p>

# 🌸 냥냥 일본어 (Nyang Nyang Japanese) - JLPT 단어장

**냥냥 일본어**는 JLPT(일본어 능력 시험) 합격을 목표로 하는 초보자부터 상급자까지, N1부터 N5까지의 필수 단어를 쉽고 체계적으로 암기할 수 있도록 도와주는 감성적인 Flutter 기반 어플리케이션입니다.

---

## ✨ 최근 업데이트: 사용자 경험의 연속성 및 UI 혁신 (v2.1)

사용자의 학습 흐름을 끊김 없이 유지하고, 더욱 세련된 디자인으로 시각적 완성도를 높였습니다.

### 1. 🎨 프리미엄 UI/UX 및 다크모드 최적화
*   **한 페이지 대시보드**: "이어서 학습"과 "진단 테스트"를 슬림한 가로 2분할 카드로 재구성하여, 스크롤 없이도 모든 핵심 메뉴를 한눈에 볼 수 있는 조화로운 홈 화면을 구현했습니다.
*   **캘린더 시인성 극대화**: 다크모드에서 흰색 배경이 튀던 문제를 해결하고, 테마 포인트 컬러와 연동된 지능형 색상 시스템을 적용하여 가독성을 높였습니다.
*   **비밀 관리자 진입로**: 지저분한 메뉴 버튼 대신 닉네임을 더블 클릭해야 열리는 숨겨진 관리자 서랍(Drawer)을 도입하여 보안성과 미관을 동시에 잡았습니다.

### 2. 🔄 완벽한 학습 연속성 (Resume Feature)
*   **이어서 학습하기(Resume Study)**: 마지막으로 공부하던 레벨과 일차(Day) 정보를 서버와 실시간 동기화하여, 앱을 재시작하거나 기기를 변경해도 즉시 마지막 지점에서 복귀할 수 있습니다.
*   **진단 테스트 세션 저장**: 테스트 도중 이탈하더라도 진행 상황이 자동 저장되며, 재진입 시 "이어 풀기"와 "새로 시작" 중 선택할 수 있는 스마트 팝업을 제공합니다.

### 3. 🛡️ 데이터 무결성을 위한 Clean Sync
*   **전수 동기화 방식 도입**: 클라우드 데이터를 가져올 때 현재 기기의 잔상을 깨끗이 비우고 서버 상태로 100% 일치시키는 'Clean Sync' 로직을 적용하여, 북마크 해제 등 삭제 기록까지 완벽하게 동기화합니다.
*   **개별 기기 설정 존중**: 학습 진도는 공유하되, 다크모드와 계절 테마 설정은 기기별 독립성을 유지하도록 동기화 대상에서 제외했습니다.

---

## 📅 오늘(2026-03-07)의 주요 개선 사항

실제 운영 과정에서 발견된 버그를 해결하고 완성도를 다듬었습니다.

### 1. 🐛 안정성 및 버그 해결
*   **공백 문제 원천 차단**: 데이터베이스 내 뜻이나 한자가 누락된 불량 단어가 문제로 출제되지 않도록 유효성 필터링 로직을 강화했습니다.
*   **로그인 브라우저 잔상 제거**: 인앱 브라우저 뷰(`inAppBrowserView`) 모드와 Redirect URL 최적화를 통해 구글 로그인 완료 후 브라우저가 즉시 닫히도록 수정했습니다.
*   **데이터 타입 에러 수정**: 세션 복구 시 발생하던 복잡한 Map 타입 캐스팅 문제를 해결하여 부드러운 이어 풀기가 가능해졌습니다.

### 2. 🎨 테마 일관성 강화
*   **통합 색상 시스템**: 팝업 내부의 아이콘, 버튼, 텍스트가 사용자가 설정한 계절 테마(봄/여름/가을/겨울) 포인트 컬러와 100% 동기화되도록 디자인을 통일했습니다.
*   **결과 카드 레이아웃**: 진단 테스트 결과가 홈 화면의 다른 카드들과 조화를 이루도록 UI 크기와 스타일을 일치시켰습니다.

---

## 📱 주요 기능

- **레벨별 단어 학습**: JLPT N1 ~ N5 단계별 필수 단어 제공
- **에빙하우스 복습 시스템 (SRS)**: 망각 곡선을 기반으로 최적화된 7단계 복습 알고리즘 적용
- **이어서 학습하기**: 언제 어디서든 마지막 학습 지점부터 즉시 복귀
- **정밀 실력 진단**: 나에게 맞는 레벨을 추천해주는 30문항 진단 테스트 (이어 풀기 지원)
- **히라가나/가타카나 학습**: 행 단위 집중 퀴즈 및 따라 쓰기 연습장
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
