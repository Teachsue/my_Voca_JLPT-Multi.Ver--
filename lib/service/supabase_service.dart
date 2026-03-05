import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../model/word.dart';
import 'database_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class SupabaseService {
  static final SupabaseClient _client = Supabase.instance.client;
  static bool _isAdmin = false;
  static bool _isMigrationComplete = false;

  static bool get isAdmin => _isAdmin;
  static bool get isMigrationComplete => _isMigrationComplete;
  static set isMigrationComplete(bool value) => _isMigrationComplete = value;

  static String? get userEmail => _client.auth.currentUser?.email;
  static bool get isGoogleLinked => _client.auth.currentUser?.identities?.any((id) => id.provider == 'google') ?? false;
  static bool get isAnonymous => !isGoogleLinked;

  static String get stableId {
    final box = Hive.box(DatabaseService.sessionBoxName);
    String? sid = box.get('stable_user_id');
    if (sid == null) {
      sid = const Uuid().v4();
      box.put('stable_user_id', sid);
    }
    return sid;
  }

  // 1. 구글 로그인
  static Future<void> signInWithGoogle() async {
    try {
      final redirectUrl = dotenv.get('REDIRECT_URL');
      await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? null : redirectUrl,
        authScreenLaunchMode: LaunchMode.platformDefault,
      );
    } catch (e) {
      debugPrint("❌ 구글 로그인 에러: $e");
    }
  }

  static Future<void> signOut() async {
    _isAdmin = false;
    _isMigrationComplete = false;
    await _client.auth.signOut();
  }

  static Future<void> refreshUser() async {
    try {
      await _client.auth.getUser();
    } catch (e) {}
  }

  static Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  // --- 프로필 관리 (닉네임 보존 최우선) ---

  static Future<Map<String, dynamic>?> getUserProfile() async {
    final String sid = stableId;
    final box = Hive.box(DatabaseService.sessionBoxName);
    final currentUser = _client.auth.currentUser;
    
    // 1. 로컬 보관 중인 닉네임
    String? localNickname = box.get('user_nickname');
    if (localNickname == null) {
      localNickname = '냥냥이${DateTime.now().millisecondsSinceEpoch % 1000}';
      await box.put('user_nickname', localNickname);
    }

    if (!isGoogleLinked) {
      _isAdmin = false;
      return {'id': sid, 'nickname': localNickname};
    }

    try {
      // 2. 서버 프로필 조회
      final response = await _client.from('profiles').select().eq('id', sid).maybeSingle();
      final String gName = currentUser?.userMetadata?['full_name'] ?? currentUser?.userMetadata?['name'] ?? '구글 유저';

      if (response != null) {
        _isAdmin = response['is_admin'] ?? false;
        
        final String? serverNickname = response['nickname'];
        
        if (serverNickname != null && serverNickname.isNotEmpty) {
          if (localNickname != serverNickname) {
            await box.put('user_nickname', serverNickname);
          }
          if (response['google_nickname'] != gName) {
            await _client.from('profiles').update({'google_nickname': gName}).eq('id', sid);
          }
          return {...response, 'nickname': serverNickname};
        }
        
        if (localNickname != null && !localNickname.startsWith('냥냥이')) {
           await _client.from('profiles').update({'nickname': localNickname, 'google_nickname': gName}).eq('id', sid);
           return {...response, 'nickname': localNickname};
        }

        await _client.from('profiles').update({'nickname': gName, 'google_nickname': gName}).eq('id', sid);
        await box.put('user_nickname', gName);
        return {...response, 'nickname': gName};
      }

      final String initialNickname = (localNickname != null && !localNickname.startsWith('냥냥이')) ? localNickname : gName;
      
      final newProfile = {
        'id': sid,
        'nickname': initialNickname,
        'auth_id': currentUser?.id,
        'google_nickname': gName,
      };
      await box.put('user_nickname', initialNickname);
      await _client.from('profiles').upsert(newProfile, onConflict: 'id');
      return newProfile;
    } catch (e) {
      debugPrint("⚠️ 동기화 실패: $e");
      return {'id': sid, 'nickname': localNickname};
    }
  }

  static Future<String?> updateNickname(String newNickname) async {
    try {
      await Hive.box(DatabaseService.sessionBoxName).put('user_nickname', newNickname);
      if (isGoogleLinked) {
        await _client.from('profiles').update({'nickname': newNickname}).eq('id', stableId);
      }
      return null;
    } catch (e) {
      return "닉네임 수정 중 오류 발생";
    }
  }

  // --- 학습 데이터 관리 ---

  /// 개별 단어 진도 업데이트 (다른 페이지에서 호출됨)
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
    if (!isGoogleLinked || _isMigrationComplete) return;
    try {
      final box = Hive.box<Word>(DatabaseService.boxName);
      final progressWords = box.values.where((w) => w.correctCount > 0 || w.incorrectCount > 0 || w.isBookmarked).toList();
      
      if (progressWords.isNotEmpty) {
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
      }
      _isMigrationComplete = true; 
      debugPrint("🚀 클라우드 동기화 완료");
    } catch (e) {
      _isMigrationComplete = true; 
      debugPrint("❌ 동기화 실패: $e");
    }
  }

  static Future<void> clearAllProgress() async {
    try {
      if (isGoogleLinked) {
        await _client.from('user_progress').delete().eq('user_id', stableId);
      }
    } catch (e) {}
  }

  static Future<void> resetWrongAnswers() async {
    try {
      if (isGoogleLinked) {
        await _client.from('user_progress').update({'incorrect_count': 0}).eq('user_id', stableId).gt('incorrect_count', 0);
      }
    } catch (e) {}
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
