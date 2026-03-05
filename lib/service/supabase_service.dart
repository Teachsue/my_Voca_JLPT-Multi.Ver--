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
    return box.get('stable_user_id') ?? _generateNewSid();
  }

  static String _generateNewSid() {
    final box = Hive.box(DatabaseService.sessionBoxName);
    final String newSid = const Uuid().v4();
    box.put('stable_user_id', newSid);
    return newSid;
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

  // --- 프로필 관리 ---

  static Future<Map<String, dynamic>?> getUserProfile() async {
    String sid = stableId;
    final box = Hive.box(DatabaseService.sessionBoxName);
    final currentUser = _client.auth.currentUser;
    
    String? localNickname = box.get('user_nickname');
    if (localNickname == null) {
      localNickname = '냥냥이${DateTime.now().millisecondsSinceEpoch % 1000}';
      await box.put('user_nickname', localNickname);
    }

    // 로컬 추천 레벨
    String? localRecLevel = box.get('recommended_level');

    if (!isGoogleLinked || currentUser == null) {
      _isAdmin = false;
      return {'id': sid, 'nickname': localNickname, 'recommended_level': localRecLevel};
    }

    try {
      final List<dynamic> profiles = await _client.from('profiles')
          .select()
          .eq('auth_id', currentUser.id)
          .order('created_at', ascending: true);

      if (profiles.isNotEmpty) {
        final existingProfile = profiles.first;
        final String serverSid = existingProfile['id'];
        final String serverNickname = existingProfile['nickname'] ?? '구글 유저';
        final String? serverRecLevel = existingProfile['recommended_level'];

        if (sid != serverSid) {
          await box.put('stable_user_id', serverSid);
          sid = serverSid;
        }

        // 닉네임 동기화
        if (localNickname != serverNickname) {
          await box.put('user_nickname', serverNickname);
        }

        // [핵심] 추천 레벨 동기화
        if (serverRecLevel != null && serverRecLevel.isNotEmpty) {
          if (localRecLevel != serverRecLevel) {
            await box.put('recommended_level', serverRecLevel);
          }
        } else if (localRecLevel != null && localRecLevel.isNotEmpty) {
          // 서버에 없으면 로컬 값을 서버에 저장
          await _client.from('profiles').update({'recommended_level': localRecLevel}).eq('id', serverSid);
        }

        final String gName = currentUser.userMetadata?['full_name'] ?? currentUser.userMetadata?['name'] ?? '구글 유저';
        if (existingProfile['google_nickname'] != gName) {
           await _client.from('profiles').update({'google_nickname': gName}).eq('id', serverSid);
        }

        _isAdmin = existingProfile['is_admin'] ?? false;
        return {...existingProfile, 'id': serverSid, 'nickname': serverNickname};
      }

      // 신규 유저 생성
      final String gName = currentUser.userMetadata?['full_name'] ?? currentUser.userMetadata?['name'] ?? '구글 유저';
      final String initialNickname = (localNickname != null && !localNickname.startsWith('냥냥이')) ? localNickname : gName;

      final newProfile = {
        'id': sid,
        'nickname': initialNickname,
        'auth_id': currentUser.id,
        'google_nickname': gName,
        'recommended_level': localRecLevel,
      };
      await box.put('user_nickname', initialNickname);
      await _client.from('profiles').upsert(newProfile, onConflict: 'id');
      return newProfile;
    } catch (e) {
      debugPrint("⚠️ 프로필 통합 에러: $e");
      return {'id': sid, 'nickname': localNickname};
    }
  }

  static String _getCurrentNickname() {
    final box = Hive.box(DatabaseService.sessionBoxName);
    return box.get('user_nickname') ?? '알 수 없는 유저';
  }

  // --- 학습 데이터 관리 ---

  static Future<void> downloadProgressFromServer() async {
    if (!isGoogleLinked) return;
    try {
      final String sid = stableId;
      final List<dynamic> response = await _client
          .from('user_progress')
          .select()
          .eq('user_id', sid);

      if (response.isEmpty) return;

      final box = Hive.box<Word>(DatabaseService.boxName);
      for (var row in response) {
        final String wordId = row['word_id'].toString();
        final String level = row['level'].toString();
        final String key = '${level}_${wordId}';
        
        final word = box.get(key);
        if (word != null) {
          word.correctCount = row['correct_count'] ?? 0;
          word.incorrectCount = row['incorrect_count'] ?? 0;
          word.isMemorized = row['is_memorized'] ?? false;
          word.isBookmarked = row['is_bookmarked'] ?? false;
          word.isWrongNote = row['is_wrong_note'] ?? false;
          word.srsStage = row['srs_stage'] ?? 0;
          word.nextReviewDate = row['next_review_date'] != null 
              ? DateTime.parse(row['next_review_date']) 
              : null;
          await word.save();
        }
      }
      debugPrint("📥 서버 데이터 복구 완료");
    } catch (e) {
      debugPrint("❌ 다운로드 실패: $e");
    }
  }

  static Future<void> uploadLocalDataToCloud() async {
    if (!isGoogleLinked) return; // 내부 _isMigrationComplete 체크 제거하여 수동 호출 보장
    try {
      final sid = stableId;
      final nickname = _getCurrentNickname();
      final box = Hive.box<Word>(DatabaseService.boxName);
      final progressWords = box.values.where((w) => w.correctCount > 0 || w.incorrectCount > 0 || w.isBookmarked || w.isWrongNote).toList();
      
      if (progressWords.isNotEmpty) {
        final List<Map<String, dynamic>> data = progressWords.map((word) => {
          'user_id': sid,
          'nickname': nickname,
          'word_id': word.id,
          'level': word.level,
          'correct_count': word.correctCount,
          'incorrect_count': word.incorrectCount,
          'is_memorized': word.isMemorized,
          'is_bookmarked': word.isBookmarked,
          'is_wrong_note': word.isWrongNote,
          'srs_stage': word.srsStage,
          'next_review_date': word.nextReviewDate?.toIso8601String(),
        }).toList();

        for (var i = 0; i < data.length; i += 500) {
          final end = (i + 500 < data.length) ? i + 500 : data.length;
          await _client.from('user_progress').upsert(data.sublist(i, end), onConflict: 'user_id, word_id');
        }
      }
      debugPrint("🚀 로컬 데이터 업로드 완료");
    } catch (e) {
      debugPrint("❌ 업로드 실패: $e");
    }
  }

  static Future<void> upsertWordProgress(Word word) async {
    if (!isGoogleLinked) return; 
    try {
      await _client.from('user_progress').upsert({
        'user_id': stableId,
        'nickname': _getCurrentNickname(),
        'word_id': word.id,
        'level': word.level,
        'correct_count': word.correctCount,
        'incorrect_count': word.incorrectCount,
        'is_memorized': word.isMemorized,
        'is_bookmarked': word.isBookmarked,
        'is_wrong_note': word.isWrongNote,
        'srs_stage': word.srsStage,
        'next_review_date': word.nextReviewDate?.toIso8601String(),
      }, onConflict: 'user_id, word_id');
    } catch (e) {}
  }

  static Future<String?> updateNickname(String newNickname) async {
    try {
      await Hive.box(DatabaseService.sessionBoxName).put('user_nickname', newNickname);
      if (isGoogleLinked) {
        await _client.from('profiles').update({'nickname': newNickname}).eq('id', stableId);
        await _client.from('user_progress').update({'nickname': newNickname}).eq('user_id', stableId);
      }
      return null;
    } catch (e) {
      return "닉네임 수정 중 오류 발생";
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
        await _client.from('user_progress').update({
          'incorrect_count': 0,
          'is_wrong_note': false
        }).eq('user_id', stableId);
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
