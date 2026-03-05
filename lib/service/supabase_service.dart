import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../model/word.dart';
import 'database_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class SupabaseService {
  static final SupabaseClient _client = Supabase.instance.client;
  static bool _isAdmin = false;
  static bool _isMigrationComplete = false; // 이번 세션에서 데이터 이사가 완료되었는지 확인

  static bool get isAdmin => _isAdmin;
  static bool get isMigrationComplete => _isMigrationComplete;
  static set isMigrationComplete(bool value) => _isMigrationComplete = value;

  static String? get userEmail => _client.auth.currentUser?.email;
  static bool get isGoogleLinked => _client.auth.currentUser?.identities?.any((id) => id.provider == 'google') ?? false;
  static bool get isAnonymous => !isGoogleLinked;

  /// 기기 고유의 변하지 않는 Stable ID (sid)
  static String get stableId {
    final box = Hive.box(DatabaseService.sessionBoxName);
    String? sid = box.get('stable_user_id');
    if (sid == null) {
      sid = const Uuid().v4();
      box.put('stable_user_id', sid);
      debugPrint("🆕 새 기기 고유 ID 생성됨: $sid");
    }
    return sid;
  }

  // 1. 구글 로그인
  static Future<void> signInWithGoogle() async {
    try {
      final redirectUrl = dotenv.get('REDIRECT_URL');
      await _client.auth.signOut(); // 기존 세션 정리
      await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectUrl,
        authScreenLaunchMode: LaunchMode.platformDefault,
      );
    } catch (e) {
      debugPrint("❌ 구글 로그인 에러: $e");
    }
  }

  // 2. 로그아웃 (Stable ID는 보존됨)
  static Future<void> signOut() async {
    _isAdmin = false;
    _isMigrationComplete = false; // 로그아웃 시 플래그 초기화
    await _client.auth.signOut();
    debugPrint("🚪 로그아웃 완료 (오프라인 모드 전환)");
  }

  static Future<void> refreshUser() async {
    try {
      await _client.auth.getUser();
    } catch (e) {
      // 비로그인 유저일 경우 실패하는 것이 정상이므로 무시
    }
  }

  static Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  // --- 프로필 관리 (지능형 동기화) ---

  static Future<Map<String, dynamic>?> getUserProfile() async {
    final String sid = stableId;
    final box = Hive.box(DatabaseService.sessionBoxName);
    final currentUser = _client.auth.currentUser;
    
    // 1. 로컬 Hive에서 현재 닉네임 확인
    String? localNickname = box.get('user_nickname');
    if (localNickname == null) {
      localNickname = '냥냥이${DateTime.now().millisecondsSinceEpoch % 1000}';
      await box.put('user_nickname', localNickname);
    }

    // 2. 비로그인 유저: 서버 통신 없이 로컬 정보 반환
    if (!isGoogleLinked) {
      _isAdmin = false;
      return {'id': sid, 'nickname': localNickname};
    }

    // 3. 구글 로그인 유저: 서버와 지능형 동기화
    try {
      final response = await _client.from('profiles').select().eq('id', sid).maybeSingle();
      
      // 구글 메타데이터에서 이름 추출
      final String gNickname = currentUser?.userMetadata?['full_name'] ?? currentUser?.userMetadata?['name'] ?? '구글 유저';

      if (response != null) {
        _isAdmin = response['is_admin'] ?? false;
        
        // [수정] 서버에 구글 연동 기록이 없거나 구글 이름 정보가 바뀐 경우 계정 연동(RPC)만 수행
        if (response['google_nickname'] == null || response['google_nickname'] != gNickname) {
          await _client.rpc('safely_link_google_account', params: {
            'p_sid': sid,
            'p_google_nickname': gNickname
          });
          
          // [중요] 연동 후에도 사용자가 이미 설정한 nickname이 있다면 유지해야 함
          // 서버에서 최신 프로필 다시 조회 (RPC가 nickname을 건드리지 않았는지 확인)
          final updatedProfile = await _client.from('profiles').select().eq('id', sid).single();
          if (localNickname != updatedProfile['nickname']) {
             await box.put('user_nickname', updatedProfile['nickname']);
          }
          return updatedProfile;
        }
        
        // [중요] 이미 연동된 유저라면 서버의 nickname을 로컬 Hive에 동기화 (서버가 상위 데이터)
        // 사용자가 마지막에 수정한 닉네임은 서버에 저장되어 있으므로 이를 가져옴
        if (localNickname != response['nickname']) {
          await box.put('user_nickname', response['nickname']);
        }
        
        return response;
      }

      // 서버에 프로필이 아예 없는 신규 유저인 경우 (최초 연동)
      final newProfile = {
        'id': sid,
        'nickname': gNickname,
        'auth_id': currentUser?.id,
        'google_nickname': gNickname,
      };
      await box.put('user_nickname', gNickname);
      await _client.from('profiles').upsert(newProfile, onConflict: 'id');
      return newProfile;
    } catch (e) {
      debugPrint("⚠️ 서버 동기화 실패 (오프라인 모드 사용): $e");
      return {'id': sid, 'nickname': localNickname};
    }
  }

  static Future<String?> updateNickname(String newNickname) async {
    try {
      // 무조건 로컬 먼저
      await Hive.box(DatabaseService.sessionBoxName).put('user_nickname', newNickname);
      
      // 연동된 유저라면 서버도 업데이트
      if (isGoogleLinked) {
        await _client.from('profiles').update({'nickname': newNickname}).eq('id', stableId);
      }
      return null;
    } catch (e) {
      return "닉네임 수정 중 오류 발생";
    }
  }

  // --- 학습 데이터 관리 ---

  static Future<void> upsertWordProgress(Word word) async {
    if (!isGoogleLinked) return; 
    try {
      await _client.from('user_progress').upsert({
        'user_id': stableId,
        'word_id': word.id,
        'level': word.level,
        'correct_count': word.correctCount,
        'incorrect_count': word.incorrectCount,
        'is_memorized': word.isMemorized,
        'is_bookmarked': word.isBookmarked,
        'srs_stage': word.srsStage,
        'next_review_date': word.nextReviewDate?.toIso8601String(),
      }, onConflict: 'user_id, word_id');
    } catch (e) {
      debugPrint("❌ 진도 서버 동기화 실패");
    }
  }

  static Future<void> uploadLocalDataToCloud() async {
    if (!isGoogleLinked) return;
    try {
      final box = Hive.box<Word>(DatabaseService.boxName);
      final progressWords = box.values.where((w) => w.correctCount > 0 || w.incorrectCount > 0 || w.isBookmarked).toList();
      if (progressWords.isEmpty) {
        _isMigrationComplete = true; // 옮길 데이터가 없어도 완료로 표시
        return;
      }

      final List<Map<String, dynamic>> data = progressWords.map((word) => {
        'user_id': stableId,
        'word_id': word.id,
        'level': word.level,
        'correct_count': word.correctCount,
        'incorrect_count': word.incorrectCount,
        'is_memorized': word.isMemorized,
        'is_bookmarked': word.isBookmarked,
        'srs_stage': word.srsStage,
        'next_review_date': word.nextReviewDate?.toIso8601String(),
      }).toList();

      for (var i = 0; i < data.length; i += 500) {
        final end = (i + 500 < data.length) ? i + 500 : data.length;
        await _client.from('user_progress').upsert(data.sublist(i, end), onConflict: 'user_id, word_id');
      }
      _isMigrationComplete = true; // 이사 완료 플래그 설정
      debugPrint("🚀 클라우드 이사 완료");
    } catch (e) {
      debugPrint("❌ 이사 실패: $e");
    }
  }

  static Future<void> clearAllProgress() async {
    try {
      if (isGoogleLinked) {
        await _client.from('user_progress').delete().eq('user_id', stableId);
      }
    } catch (e) {
      debugPrint("❌ 서버 데이터 초기화 실패");
    }
  }

  static Future<void> resetWrongAnswers() async {
    try {
      if (isGoogleLinked) {
        await _client.from('user_progress').update({'incorrect_count': 0}).eq('user_id', stableId).gt('incorrect_count', 0);
      }
    } catch (e) {
      debugPrint("❌ 서버 오답 초기화 실패");
    }
  }

  static Future<Map<String, dynamic>?> getAppConfig() async {
    try {
      return await _client.from('app_config').select().single();
    } catch (e) {
      return null;
    }
  }

  static Future<List<Word>> fetchAllWords() async {
    try {
      final List<dynamic> response = await _client.from('words').select();
      return response.map((json) => Word.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  static Future<void> bulkUpsertWords(List<Word> words) async {
    try {
      final List<Map<String, dynamic>> data = words.map((w) => {
        'id': w.id, 'kanji': w.kanji, 'kana': w.kana, 'meaning': w.meaning, 'level': w.level, 'korean_pronunciation': w.koreanPronunciation,
      }).toList();
      for (var i = 0; i < data.length; i += 1000) {
        final end = (i + 1000 < data.length) ? i + 1000 : data.length;
        await _client.from('words').upsert(data.sublist(i, end), onConflict: 'id');
      }
    } catch (e) {
      rethrow;
    }
  }
}
