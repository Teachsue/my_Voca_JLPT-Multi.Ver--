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

  static Future<void> signInWithGoogle() async {
    try {
      final redirectUrl = dotenv.get('REDIRECT_URL');
      await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? null : redirectUrl,
        authScreenLaunchMode: LaunchMode.externalApplication,
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
      final session = _client.auth.currentSession;
      if (session == null) return;
      
      // 토큰 만료가 임박했거나 만료된 경우 강제 갱신 시도
      if (session.isExpired) {
        debugPrint("🔄 세션 만료됨. 토큰 갱신 시도 중...");
        await _client.auth.refreshSession();
      } else {
        await _client.auth.getUser();
      }
    } catch (e) {
      debugPrint("⚠️ 세션 갱신 실패: $e");
      // 리프레시 토큰까지 만료된 경우 로그아웃 처리하여 깨끗한 상태로 만듦
      if (e.toString().contains('refresh_token_not_found') || e.toString().contains('Invalid Refresh Token')) {
        await signOut();
      }
    }
  }

  /// [신규] 모든 Supabase 쿼리 실행 전 세션 체크 및 에러 핸들링을 위한 래퍼
  static Future<T?> _safeRequest<T>(Future<T> Function() request) async {
    try {
      await refreshUser(); // 요청 전 세션 체크
      return await request();
    } catch (e) {
      if (e is PostgrestException && (e.code == 'pgrst303' || e.message.contains('JWT expired'))) {
        debugPrint("🔑 JWT 만료 감지 (pgrst303). 세션 재갱신 후 재시도...");
        try {
          await _client.auth.refreshSession();
          return await request(); // 1회 재시도
        } catch (retryError) {
          debugPrint("❌ 세션 재갱신 후에도 요청 실패: $retryError");
          return null;
        }
      }
      debugPrint("❌ Supabase 요청 에러: $e");
      return null;
    }
  }

  static Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  // --- 프로필 관리 (자동 동기화 금지) ---

  static Future<Map<String, dynamic>?> fetchRemoteProfile() async {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null) return null;
    
    return await _safeRequest(() async {
      final List<dynamic> profiles = await _client
          .from('profiles')
          .select()
          .eq('auth_id', currentUser.id)
          .order('created_at', ascending: true);
      return profiles.isNotEmpty ? profiles.first : null;
    });
  }

  static Future<void> syncStableIdWithServer(String serverSid) async {
    final box = Hive.box(DatabaseService.sessionBoxName);
    await box.put('stable_user_id', serverSid);
    debugPrint("🔄 기기 ID 통합 완료: $serverSid");
  }

  static Future<void> forcePushLocalToServer(String serverSid) async {
    try {
      await _client.from('user_progress').delete().eq('user_id', serverSid);
      
      final box = Hive.box(DatabaseService.sessionBoxName);
      final String nickname = box.get('user_nickname') ?? '알 수 없는 유저';
      final String? recLevel = box.get('recommended_level');
      
      await _client.from('profiles').update({
        'nickname': nickname,
        'recommended_level': recLevel,
      }).eq('id', serverSid);

      await syncStableIdWithServer(serverSid);
      await uploadLocalDataToCloud();
      debugPrint("🚀 [강제 업로드] 로컬 데이터로 서버를 완벽히 덮어썼습니다.");
    } catch (e) {
      debugPrint("❌ 강제 업로드 에러: $e");
    }
  }

  static Future<void> forcePullServerToLocal(String serverSid) async {
    try {
      await syncStableIdWithServer(serverSid);
      await downloadProgressFromServer();
      debugPrint("📥 [강제 다운로드] 서버 데이터를 로컬에 완벽히 이식했습니다.");
    } catch (e) {
      debugPrint("❌ 강제 다운로드 에러: $e");
    }
  }

  /// [핵심 수정] 서버 데이터를 조회만 하고 로컬 Hive를 절대 건드리지 않음
  static Future<Map<String, dynamic>?> getUserProfile() async {
    final box = Hive.box(DatabaseService.sessionBoxName);
    final currentUser = _client.auth.currentUser;
    
    // 1. 로컬 닉네임 기본값 보장
    if (box.get('user_nickname') == null) {
      await box.put('user_nickname', '냥냥이${DateTime.now().millisecondsSinceEpoch % 1000}');
    }

    // 2. 비로그인 유저는 로컬 정보 반환
    if (!isGoogleLinked || currentUser == null) {
      _isAdmin = false;
      return {'id': stableId, 'nickname': box.get('user_nickname'), 'recommended_level': box.get('recommended_level')};
    }

    // 3. 로그인 유저: 서버 프로필 조회
    final existingProfile = await fetchRemoteProfile();
    if (existingProfile != null) {
      _isAdmin = existingProfile['is_admin'] ?? false;
      
      // [수정] 아직 동기화 선택 전(isMigrationComplete == false)이면서 기기 ID가 통합되지 않았다면
      // 화면이 깜빡이거나 바뀌는 것을 막기 위해 '현재 로컬 데이터'를 반환합니다.
      if (!isMigrationComplete && existingProfile['id'] != stableId) {
        return {
          'id': stableId, 
          'nickname': box.get('user_nickname'), 
          'recommended_level': box.get('recommended_level')
        };
      }
      return existingProfile; 
    }

    // 4. 서버에 아예 없는 신규 유저라면 현재 로컬 기준으로 생성
    final String gName = currentUser.userMetadata?['full_name'] ?? currentUser.userMetadata?['name'] ?? '구글 유저';
    final String initialNickname = box.get('user_nickname') ?? gName;
    final String? localRecLevel = box.get('recommended_level');

    final newProfile = {
      'id': stableId,
      'nickname': initialNickname,
      'auth_id': currentUser.id,
      'google_nickname': gName,
      'recommended_level': localRecLevel,
    };
    await _client.from('profiles').upsert(newProfile, onConflict: 'id');
    return newProfile;
  }

  static Future<bool> hasExistingData(String sid) async {
    try {
      final progress = await _client.from('user_progress').select('word_id').eq('user_id', sid).limit(1);
      if (progress.isNotEmpty) return true;
      final profile = await _client.from('profiles').select('recommended_level').eq('id', sid).maybeSingle();
      if (profile != null && profile['recommended_level'] != null) return true;
      return false;
    } catch (e) { return false; }
  }

  // --- 동기화 방향성 강제 (Push vs Pull) ---

  /// [서버 데이터 불러오기] 서버 데이터를 로컬 Hive에 강제 이식 (사용자 선택 시에만 실행)
  static Future<void> downloadProgressFromServer() async {
    if (!isGoogleLinked) return;
    try {
      final String sid = stableId;
      final box = Hive.box(DatabaseService.sessionBoxName);
      
      // 1. 프로필 정보(닉네임, 추천 레벨) 강제 이식
      final profile = await fetchRemoteProfile();
      if (profile != null) {
        if (profile['nickname'] != null) await box.put('user_nickname', profile['nickname']);
        if (profile['recommended_level'] != null) await box.put('recommended_level', profile['recommended_level']);
      }

      // 2. 단어 진도 데이터 강제 이식
      final List<dynamic> response = await _client.from('user_progress').select().eq('user_id', sid);
      final wordBox = Hive.box<Word>(DatabaseService.boxName);
      for (var row in response) {
        try {
          final String hiveKey = '${row['level']}_${row['word_id']}';
          final word = wordBox.get(hiveKey);
          if (word != null) {
            word.correctCount = row['correct_count'] as int? ?? 0;
            word.incorrectCount = row['incorrect_count'] as int? ?? 0;
            word.isMemorized = row['is_memorized'] as bool? ?? false;
            word.isBookmarked = row['is_bookmarked'] as bool? ?? false;
            word.isWrongNote = row['is_wrong_note'] as bool? ?? false;
            word.srsStage = row['srs_stage'] as int? ?? 0;
            final String? rawDate = row['next_review_date'] as String?;
            word.nextReviewDate = rawDate != null ? DateTime.tryParse(rawDate) : null;
            await word.save();
          }
        } catch (e) {}
      }
      debugPrint("📥 [불러오기 완료] 서버 데이터가 로컬을 완전히 대체했습니다.");
    } catch (e) { debugPrint("❌ 다운로드 실패: $e"); }
  }

  /// [로컬 데이터 유지] 현재 로컬 상태를 서버에 강제로 덮어씌움 (사용자 선택 시에만 실행)
  static Future<void> uploadLocalDataToCloud() async {
    if (!isGoogleLinked) return;
    try {
      final sid = stableId;
      final box = Hive.box(DatabaseService.sessionBoxName);
      final String nickname = box.get('user_nickname') ?? '알 수 없는 유저';
      final String? recLevel = box.get('recommended_level');

      // 1. 서버 프로필을 현재 로컬 값으로 강제 업데이트 (Push)
      await _client.from('profiles').update({
        'nickname': nickname,
        'recommended_level': recLevel,
      }).eq('id', sid);

      // 2. 단어 진도 데이터 강제 업로드 (Push)
      final wordBox = Hive.box<Word>(DatabaseService.boxName);
      final progressWords = wordBox.values.where((w) => 
        w.correctCount > 0 || w.incorrectCount > 0 || w.isBookmarked || w.isWrongNote || w.isMemorized
      ).toList();
      
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
      debugPrint("🚀 [유지 완료] 현재 기기 데이터로 서버 기록을 최신화했습니다.");
    } catch (e) { debugPrint("❌ 업로드 실패: $e"); }
  }

  static Future<void> upsertWordProgress(Word word) async {
    if (!isGoogleLinked) return; 
    try {
      await _client.from('user_progress').upsert({
        'user_id': stableId,
        'nickname': Hive.box(DatabaseService.sessionBoxName).get('user_nickname'),
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

  static Future<void> updateNickname(String newNickname) async {
    try {
      await Hive.box(DatabaseService.sessionBoxName).put('user_nickname', newNickname);
      if (isGoogleLinked) {
        await _client.from('profiles').update({'nickname': newNickname}).eq('id', stableId);
        await _client.from('user_progress').update({'nickname': newNickname}).eq('user_id', stableId);
      }
    } catch (e) {}
  }

  static Future<void> resetRecommendedLevel() async {
    try {
      await Hive.box(DatabaseService.sessionBoxName).delete('recommended_level');
      if (isGoogleLinked) {
        await _client.from('profiles').update({'recommended_level': null}).eq('id', stableId);
      }
    } catch (e) {}
  }

  static Future<void> clearAllProgress() async {
    try {
      if (isGoogleLinked) {
        await _client.from('user_progress').delete().eq('user_id', stableId);
        await _client.from('profiles').update({'recommended_level': null}).eq('id', stableId);
      }
    } catch (e) {}
  }

  static Future<void> resetWrongAnswers() async {
    try {
      if (isGoogleLinked) {
        await _client.from('user_progress').update({'incorrect_count': 0, 'is_wrong_note': false}).eq('user_id', stableId);
      }
    } catch (e) {}
  }

  static Future<Map<String, dynamic>?> getAppConfig() async {
    try { return await _client.from('app_config').select().single(); } catch (e) { return null; }
  }

  static Future<List<Word>> fetchAllWords() async {
    try {
      final List<dynamic> response = await _client.from('words').select();
      return response.map((json) => Word.fromJson(json)).toList();
    } catch (e) { return []; }
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
    } catch (e) { rethrow; }
  }
}
