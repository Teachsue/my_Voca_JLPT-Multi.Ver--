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
      
      // 기존 세션이 꼬이지 않도록 정리 후 로그인
      await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        // 윈도우 앱에서는 redirectTo를 명시하여 딥링크 처리가 원활하게 함
        redirectTo: kIsWeb ? null : redirectUrl,
        authScreenLaunchMode: LaunchMode.externalApplication, // 외부 브라우저 사용 권장
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

  // --- 프로필 관리 (기기 변경 시에도 닉네임 보존) ---

  static Future<Map<String, dynamic>?> getUserProfile() async {
    final String sid = stableId;
    final box = Hive.box(DatabaseService.sessionBoxName);
    final currentUser = _client.auth.currentUser;
    
    // 1. 로컬 보관 중인 닉네임 확인
    String? localNickname = box.get('user_nickname');
    if (localNickname == null) {
      localNickname = '냥냥이${DateTime.now().millisecondsSinceEpoch % 1000}';
      await box.put('user_nickname', localNickname);
    }

    // 2. 비로그인 유저: 서버 통신 없이 로컬 정보 반환
    if (!isGoogleLinked || currentUser == null) {
      _isAdmin = false;
      return {'id': sid, 'nickname': localNickname};
    }

    try {
      // 3. 서버 프로필 조회 (먼저 현재 기기 ID로 조회)
      var response = await _client.from('profiles').select().eq('id', sid).maybeSingle();
      final String gName = currentUser.userMetadata?['full_name'] ?? currentUser.userMetadata?['name'] ?? '구글 유저';

      // [핵심] 만약 현재 기기(sid)로 프로필이 없다면, 동일한 구글 계정(auth_id)을 쓰는 다른 기기의 프로필이 있는지 확인
      if (response == null) {
        final existingByAuth = await _client.from('profiles')
            .select()
            .eq('auth_id', currentUser.id)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
            
        if (existingByAuth != null) {
          debugPrint("📱 기존 기기에서 사용하던 프로필 발견: ${existingByAuth['nickname']}");
          response = existingByAuth;
          
          // 새 기기(sid) 정보로도 이 닉네임을 서버에 등록 (기기 간 동기화)
          await _client.from('profiles').upsert({
            'id': sid,
            'nickname': existingByAuth['nickname'],
            'auth_id': currentUser.id,
            'google_nickname': gName,
          }, onConflict: 'id');
        }
      }

      if (response != null) {
        _isAdmin = response['is_admin'] ?? false;
        final String? serverNickname = response['nickname'];
        
        // 닉네임이 있다면 로컬에 즉시 동기화 (구글 이름보다 우선)
        if (serverNickname != null && serverNickname.isNotEmpty) {
          if (localNickname != serverNickname) {
            await box.put('user_nickname', serverNickname);
          }
          // google_nickname 필드만 정보용으로 업데이트
          if (response['google_nickname'] != gName) {
            await _client.from('profiles').update({'google_nickname': gName}).eq('id', response['id']);
          }
          return {...response, 'nickname': serverNickname};
        }
      }

      // 4. 정말로 아무런 기록이 없는 신규 유저인 경우에만 구글 이름 사용
      final String initialNickname = (localNickname != null && !localNickname.startsWith('냥냥이')) ? localNickname : gName;
      
      final newProfile = {
        'id': sid,
        'nickname': initialNickname,
        'auth_id': currentUser.id,
        'google_nickname': gName,
      };
      await box.put('user_nickname', initialNickname);
      await _client.from('profiles').upsert(newProfile, onConflict: 'id');
      return newProfile;
    } catch (e) {
      debugPrint("⚠️ 프로필 동기화 에러: $e");
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
