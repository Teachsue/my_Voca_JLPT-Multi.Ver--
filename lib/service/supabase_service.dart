import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../model/word.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class SupabaseService {
  static final SupabaseClient _client = Supabase.instance.client;
  static String? _lastAuthError; // 마지막 인증 에러 저장
  static bool _isAdmin = false; // 관리자 여부 캐시

  static bool get isAdmin => _isAdmin;
  static String? get lastAuthError => _lastAuthError;
  static void clearAuthError() => _lastAuthError = null;

  // 인증 상태 리스너 설정 (main.dart 등에서 초기화 시 호출 권장)
  static void initAuthListener(Function(String) onError) {
    _client.auth.onAuthStateChange.listen((data) {
      // 에러가 포함된 딥링크 응답 처리 (실제 SDK 내부 에러는 여기서 잡기 어려울 수 있음)
    }, onError: (error) {
      if (error is AuthException) {
        _lastAuthError = error.message;
        onError(error.message);
      }
    });
  }

  // 유저 ID 가져오기
  static String? get userId => _client.auth.currentUser?.id;
  
  // 현재 유저 객체
  static User? get currentUser => _client.auth.currentUser;

  // 현재 유저가 익명(게스트)인지 확인
  static bool get isAnonymous => _client.auth.currentUser?.isAnonymous ?? true;
  
  // 현재 연동된 인증 수단 목록
  static List<UserIdentity> get identities => _client.auth.currentUser?.identities ?? [];
  
  // 구글 연동 여부 확인
  static bool get isGoogleLinked => identities.any((id) => id.provider == 'google');

  // 유저 정보 강제 새로고침 (서버에서 최신 identities 등 동기화)
  static Future<void> refreshUser() async {
    try {
      await _client.auth.getUser();
      debugPrint("🔄 유저 정보 동기화 완료: ${identities.map((i) => i.provider).toList()}");
    } catch (e) {
      debugPrint("❌ 유저 정보 동기화 실패: $e");
    }
  }

  // 유저 이메일 가져오기
  static String? get userEmail => _client.auth.currentUser?.email;

  // 1. 익명 로그인
  static Future<void> signInAnonymously() async {
    if (_client.auth.currentUser == null) {
      try {
        await _client.auth.signInAnonymously();
        debugPrint("✅ Supabase 익명 로그인 성공: ${userId}");
      } catch (e) {
        debugPrint("❌ Supabase 로그인 실패: $e");
      }
    }
  }

  // 2. 구글 계정 연동 (현재 익명 계정에 연결)
  static Future<bool> linkWithGoogle() async {
    try {
      final redirectUrl = dotenv.get('REDIRECT_URL');
      await _client.auth.linkIdentity(
        OAuthProvider.google,
        redirectTo: redirectUrl,
      );
      return true;
    } catch (e) {
      debugPrint("❌ 구글 계정 연동 시도 에러: $e");
      return false;
    }
  }

  // 2-1. 구글 계정으로 로그인 (기존 계정이 있을 때 사용)
  static Future<void> signInWithGoogle() async {
    try {
      final redirectUrl = dotenv.get('REDIRECT_URL');
      await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectUrl,
      );
      debugPrint("✅ 구글 로그인 프로세스 시작...");
    } catch (e) {
      debugPrint("❌ 구글 로그인 실패: $e");
    }
  }

  // 3. 로그아웃
  static Future<void> signOut() async {
    _isAdmin = false;
    await _client.auth.signOut();
    await signInAnonymously();
  }

  // --- 프로필 관리 ---

  static Future<Map<String, dynamic>?> getUserProfile() async {
    final currentUserId = userId;
    if (currentUserId == null) {
      _isAdmin = false;
      return {'nickname': '냥냥이...'};
    }

    try {
      final response = await _client.from('profiles').select().eq('id', currentUserId).maybeSingle();
      
      if (response != null) {
        _isAdmin = response['is_admin'] ?? false; // 관리자 여부 저장
        return response;
      }

      if (response == null) {
        _isAdmin = false;
        try {
          // 서버에서 다음 번호표 닉네임 가져오기 (냥냥이1, 냥냥이2...)
          final String uniqueNickname = await _client.rpc('get_next_anonymous_nickname');
          
          final newProfile = {'id': currentUserId, 'nickname': uniqueNickname};
          await Future.delayed(const Duration(milliseconds: 500)); 
          await _client.from('profiles').upsert(newProfile);
          return newProfile;
        } catch (insertError) {
          debugPrint("⚠️ 프로필 자동 생성 실패: $insertError");
          return {'nickname': '냥냥이'};
        }
      }
      return response;
    } catch (e) {
      debugPrint("❌ 프로필 로드 실패: $e");
      return {'nickname': '냥냥이'};
    }
  }

  static Future<String?> updateNickname(String newNickname) async {
    final currentUserId = userId;
    if (currentUserId == null) return "로그인이 필요합니다.";
    try {
      await _client.from('profiles').upsert({
        'id': currentUserId,
        'nickname': newNickname,
        // 'updated_at' 제거 (서버 트리거가 처리)
      });
      return null; // 성공
    } catch (e) {
      debugPrint("❌ 닉네임 수정 실패: $e");
      if (e.toString().contains('unique_nickname')) {
        return "이미 사용 중인 닉네임입니다.";
      }
      return "닉네임 수정 중 오류가 발생했습니다.";
    }
  }

  // --- 학습 데이터 관리 ---

  static Future<void> upsertWordProgress(Word word) async {
    final currentUserId = userId;
    if (currentUserId == null) {
      debugPrint("⚠️ 로그인 정보가 없어 업로드를 건너뜁니다.");
      return;
    }

    try {
      await _client.from('user_progress').upsert({
        'user_id': currentUserId,
        'word_id': word.id,
        'level': word.level,
        'correct_count': word.correctCount,
        'incorrect_count': word.incorrectCount,
        'is_memorized': word.isMemorized,
        'is_bookmarked': word.isBookmarked,
        'srs_stage': word.srsStage,
        'next_review_date': word.nextReviewDate?.toIso8601String(),
        // 'updated_at' 제거 (서버 트리거가 처리)
      }, onConflict: 'user_id, word_id');
      debugPrint("☁️ 서버 동기화 완료: ID ${word.id} (${word.kanji})");
    } catch (e) {
      debugPrint("❌ 데이터 업로드 실패: $e");
      if (e is PostgrestException) {
        debugPrint("   - 에러 코드: ${e.code}");
        debugPrint("   - 에러 상세: ${e.details}");
        debugPrint("   - 에러 메시지: ${e.message}");
      }
    }
  }

  /// 서버의 모든 학습 기록 삭제 (북마크 포함 완전 초기화)
  static Future<void> clearAllProgress() async {
    if (userId == null) return;
    try {
      await _client.from('user_progress').delete().eq('user_id', userId!);
      debugPrint("🧹 서버 학습 데이터 완전 초기화 완료");
    } catch (e) {
      debugPrint("❌ 서버 데이터 초기화 실패: $e");
    }
  }

  /// 서버의 오답 기록만 일괄 초기화 (오답 수만 0으로)
  static Future<void> resetWrongAnswers() async {
    if (userId == null) return;
    try {
      await _client.from('user_progress')
          .update({'incorrect_count': 0})
          .eq('user_id', userId!)
          .gt('incorrect_count', 0); // 오답이 있는 것들만 골라서 0으로
      debugPrint("🧹 서버 오답 기록 일괄 초기화 완료");
    } catch (e) {
      debugPrint("❌ 서버 오답 기록 초기화 실패: $e");
    }
  }

  static Future<List<Map<String, dynamic>>> fetchAllProgress() async {
    if (userId == null) return [];
    try {
      final response = await _client.from('user_progress').select().eq('user_id', userId!);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint("❌ 데이터 불러오기 실패: $e");
      return [];
    }
  }

  static Future<Map<String, dynamic>?> getAppConfig() async {
    try {
      final response = await _client.from('app_config').select().single();
      return response;
    } catch (e) {
      debugPrint("❌ 설정 로드 실패: $e");
      return null;
    }
  }

  /// 서버의 모든 마스터 단어 데이터 가져오기 (동기화용)
  static Future<List<Word>> fetchAllWords() async {
    try {
      final List<dynamic> response = await _client.from('words').select();
      return response.map((json) => Word.fromJson(json)).toList();
    } catch (e) {
      debugPrint("❌ 서버 단어 로드 실패: $e");
      return [];
    }
  }

  // --- 단어 마스터 데이터 관리 (Admin) ---

  /// 로컬 JSON 데이터를 Supabase 'words' 테이블로 마이그레이션
  static Future<void> bulkUpsertWords(List<Word> words) async {
    try {
      final List<Map<String, dynamic>> data = words.map((w) => {
        'id': w.id,
        'kanji': w.kanji,
        'kana': w.kana,
        'meaning': w.meaning,
        'level': w.level,
        'korean_pronunciation': w.koreanPronunciation,
      }).toList();

      // 1000개씩 끊어서 업로드 (Supabase 제한 대비)
      for (var i = 0; i < data.length; i += 1000) {
        final end = (i + 1000 < data.length) ? i + 1000 : data.length;
        final chunk = data.sublist(i, end);
        await _client.from('words').upsert(chunk, onConflict: 'id');
        debugPrint("✅ ${i + chunk.length}/${data.length}개 단어 업로드 중...");
      }
      
      debugPrint("✨ 총 ${words.length}개 단어 마이그레이션 완료");
    } catch (e) {
      debugPrint("❌ 단어 대량 업로드 실패: $e");
      rethrow;
    }
  }
}
