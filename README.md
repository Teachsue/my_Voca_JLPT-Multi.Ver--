<p align="center">
  <img src="assets/icon.png" width="120" height="120" alt="냥냥 일본어 로고">
</p>

# 🌸 냥냥 일본어 (Nyang Nyang Japanese) - JLPT 단어장

**냥냥 일본어**는 JLPT(일본어 능력 시험) 합격을 목표로 하는 모든 학습자를 위한 감성적인 일본어 학습 앱입니다. N1부터 N5까지의 필수 단어를 체계적인 복습 알고리즘과 아름다운 계절 테마 속에서 즐겁게 암기할 수 있습니다.

---

## 🔥 최신 대규모 업데이트 (v3.0 - 2026.03.09)

사용자의 목소리를 적극 반영하여 앱의 안정성을 "Zero Error" 수준으로 끌어올리고, 시각적 경험을 한 단계 진화시켰습니다.

### 1. 🔐 인증 시스템의 완벽한 진화
*   **네이티브 구글 로그인 도입**: 기존 브라우저 방식의 번거로움을 없애고, 안드로이드 시스템 계정 선택창을 통한 매끄러운 인증 흐름을 구축했습니다.
*   **하이브리드 로그인 폴백**: 다양한 환경에서도 인증이 중단되지 않도록 네이티브와 브라우저 기반 OAuth 방식을 유기적으로 결합했습니다.

### 2. 🧠 지능형 학습 로직 고도화
*   **자정까지 고정되는 "오늘의 단어"**: 매일 N1~N5 범위에서 10개의 단어를 엄선하며, 당일 자정까지 목록이 고정되어 학습의 집중도를 높입니다.
*   **전 모드 퀴즈 이어풀기(Resume)**: 학습 도중 전화를 받거나 앱이 종료되어도 문제 번호, 점수, 정답 기록을 완벽히 보존하여 언제든 이어서 학습할 수 있습니다.
*   **Push-then-Pull 데이터 보호**: 계정 연동 시 로컬 오답노트가 유실되지 않도록 로컬 데이터를 먼저 서버에 병합한 뒤 다운로드하는 안전한 동기화 시퀀스를 적용했습니다.

### 3. 🎭 프리미엄 UI/UX 및 딥 다크 테마
*   **눈이 편안한 딥 다크(Deep Dark)**: 다크 모드 시 단순한 투명도가 아닌, 깊은 무채색 배경과 톤다운된 텍스트를 사용하여 야간 학습의 피로도를 획기적으로 줄였습니다.
*   **계절별 포인트 컬러 시스템**: 앱의 모든 버튼, 배지, 진행 바가 현재 계절 테마(봄, 여름, 가을, 겨울)와 라이트/다크 모드에 맞춰 실시간으로 반응합니다.
*   **프리미엄 결과 화면**: 만점 시 화려한 트로피 UI와 함께 성취감을 극대화하고, 오답 시에는 계층적인 복습 카드를 통해 효율적인 재학습을 돕습니다.

### 4. 🛠️ 기술적 완성도 및 버그 제로
*   **빌드 충돌 해결**: `setState()` 빌드 사이클 에러를 완벽히 차단하여 어떤 상황에서도 앱이 멈추지 않는 안정성을 확보했습니다.
*   **깜빡임 방지(ValueKey)**: 문제 전환 시 이전 정답의 잔상이 남지 않도록 위젯 렌더링 최적화를 완료했습니다.
*   **레이아웃 유연성**: 텍스트 길이에 상관없이 오버플로우가 발생하지 않도록 `Wrap`과 `FittedBox` 기반의 반응형 디자인을 적용했습니다.

---

## 📱 주요 기능

- **레벨별 단어 학습**: JLPT N1 ~ N5 단계별 필수 단어 제공
- **오늘의 단어 (Fixed)**: 매일 매일 새롭게 제공되는 고정 단어 10개 퀴즈
- **에빙하우스 복습 시스템 (SRS)**: 망각 곡선을 기반으로 최적화된 7단계 복습 알고리즘
- **이어서 학습하기**: 레벨별 마지막 학습 지점을 기억하고 자연스러운 내비게이션 제공
- **정밀 실력 진단**: 나에게 맞는 레벨을 추천해주는 30문항 진단 테스트 (세션 보존)
- **학습 통계 & 캘린더**: 서버와 실시간 동기화되는 학습 리포트 및 성공 도장

---

## 📸 Screenshots

| 메인 화면 | 단어 리스트 | 퀴즈 화면 |
| :---: | :---: | :---: |
| <img src="screenshots/home.png" width="200"> | <img src="screenshots/list.png" width="200"> | <img src="screenshots/quiz.png" width="200"> |

| 오답노트 | 실력 테스트 | 결과 화면 |
| :---: | :---: | :---: |
| <img src="screenshots/wrong.png" width="200"> | <img src="screenshots/test.png" width="200"> | <img src="screenshots/stats.png" width="200"> |

---

## 🛠 Tech Stack

- **Framework**: [Flutter](https://flutter.dev/) (Material 3)
- **Language**: [Dart](https://dart.dev/)
- **Database**: 
  - [Hive](https://pub.dev/packages/hive) (Local NoSQL for Offline First)
  - [Supabase PostgREST](https://supabase.com/) (Cloud Sync & Auth)
- **State Management**: [Provider](https://pub.dev/packages/provider)
- **Auth**: Google Sign-In (Native & OAuth)

---

## 🚀 시작하기

1. 저장소 클론: `git clone https://github.com/your-username/my_voca_japan_app.git`
2. 패키지 설치: `flutter pub get`
3. 환경 설정: `.env` 파일에 Supabase 및 Google Client ID 등록
4. 앱 실행: `flutter run`

---
*JLPT 합격을 응원합니다! 냥냥 일본어와 함께 즐겁게 공부하세요! 🐾 🇯🇵*
