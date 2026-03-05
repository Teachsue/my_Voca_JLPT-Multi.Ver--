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

  // --- 프로필 및 데이터 통합 (기기 변경 시 핵심 로직) ---

  static Future<Map<String, dynamic>?> getUserProfile() async {
    String sid = stableId;
    final box = Hive.box(DatabaseService.sessionBoxName);
    final currentUser = _client.auth.currentUser;
    
    String? localNickname = box.get('user_nickname');
    if (localNickname == null) {
      localNickname = '냥냥이${DateTime.now().millisecondsSinceEpoch % 1000}';
      await box.put('user_nickname', localNickname);
    }

    if (!isGoogleLinked || currentUser == null) {
      _isAdmin = false;
      return {'id': sid, 'nickname': localNickname};
    }

    try {
      // [핵심 로직] 이 구글 계정(auth_id)으로 생성된 프로필들을 모두 조회
      // maybeSingle() 대신 select()를 사용하여 여러 기기 기록이 있어도 에러 방지
      final List<dynamic> profiles = await _client.from('profiles')
          .select()
          .eq('auth_id', currentUser.id)
          .order('created_at', ascending: true); // 가장 먼저 생성된(원본) 프로필을 첫 번째로

      if (profiles.isNotEmpty) {
        // [1단계] 가장 오래된(원본) 프로필 정보 채택
        final existingProfile = profiles.first;
        final String serverSid = existingProfile['id'];
        final String serverNickname = existingProfile['nickname'] ?? '구글 유저';

        // [2단계] 현재 기기 ID(sid)가 원본 서버 ID(serverSid)와 다르면 강제 교체
        if (sid != serverSid) {
          debugPrint("🔄 기기 통합 수행: $sid -> $serverSid (원본 닉네임: $serverNickname)");
          await box.put('stable_user_id', serverSid);
          sid = serverSid; // 이후 로직에서 교체된 sid 사용
        }

        // 로컬 닉네임 동기화
        if (localNickname != serverNickname) {
          await box.put('user_nickname', serverNickname);
        }

        // 구글 메타데이터 이름 업데이트 (참고용)
        final String gName = currentUser.userMetadata?['full_name'] ?? currentUser.userMetadata?['name'] ?? '구글 유저';
        if (existingProfile['google_nickname'] != gName) {
           await _client.from('profiles').update({'google_nickname': gName}).eq('id', serverSid);
        }

        _isAdmin = existingProfile['is_admin'] ?? false;
        return {...existingProfile, 'id': serverSid, 'nickname': serverNickname};
      }

      // [3단계] 서버에 프로필이 전혀 없는 신규 유저인 경우 (최초 연동)
      final String gName = currentUser.userMetadata?['full_name'] ?? currentUser.userMetadata?['name'] ?? '구글 유저';
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
      debugPrint("⚠️ 프로필 통합 에러: $e");
      return {'id': sid, 'nickname': localNickname};
    }
  }

  // --- 학습 데이터 관리 (다운로드/업로드) ---

  /// 서버의 진도 데이터를 로컬로 내려받기 (기기 변경 시 복구 핵심)
  static Future<void> downloadProgressFromServer() async {
    if (!isGoogleLinked) return;
    try {
      final String sid = stableId; // 통합된 sid를 사용함
      debugPrint("📥 서버 데이터 다운로드 시도 (SID: $sid)");
      
      final List<dynamic> response = await _client
          .from('user_progress')
          .select()
          .eq('user_id', sid);

      if (response.isEmpty) {
        debugPrint("📥 서버에 저장된 진도 데이터가 없습니다.");
        return;
      }

      final box = Hive.box<Word>(DatabaseService.boxName);
      int count = 0;
      
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
          word.srsStage = row['srs_stage'] ?? 0;
          word.nextReviewDate = row['next_review_date'] != null 
              ? DateTime.parse(row['next_review_date']) 
              : null;
          await word.save();
          count++;
        }
      }
      debugPrint("📥 서버 데이터 복구 완료 ($count개 단어)");
    } catch (e) {
      debugPrint("❌ 서버 데이터 다운로드 실패: $e");
    }
  }

  static Future<void> uploadLocalDataToCloud() async {
    if (!isGoogleLinked) return;
    try {
      final sid = stableId;
      final box = Hive.box<Word>(DatabaseService.boxName);
      final progressWords = box.values.where((w) => w.correctCount > 0 || w.incorrectCount > 0 || w.isBookmarked).toList();
      
      if (progressWords.isEmpty) {
        _isMigrationComplete = true;
        return;
      }

      final List<Map<String, dynamic>> data = progressWords.map((word) => {
        'user_id': sid,
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
      _isMigrationComplete = true; 
      debugPrint("🚀 클라우드 동기화 완료");
    } catch (e) {
      _isMigrationComplete = true; 
      debugPrint("❌ 동기화 실패: $e");
    }
  }

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
