import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../model/word.dart';
import 'database_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';

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

  static Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

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

  static Future<T?> _safeRequest<T>(Future<T> Function() request) async {
    try {
      return await request();
    } catch (e) {
      debugPrint("❌ Supabase 에러: $e");
      return null;
    }
  }

  static Future<void> refreshUser() async {
    try { await _client.auth.refreshSession(); } catch (e) {}
  }

  static Future<void> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        await _client.auth.signInWithOAuth(OAuthProvider.google, redirectTo: dotenv.get('REDIRECT_URL'));
        return;
      }

      debugPrint("🚀 네이티브 구글 로그인 시도 중...");
      final GoogleSignIn googleSignIn = GoogleSignIn(
        serverClientId: dotenv.get('GOOGLE_WEB_CLIENT_ID'),
      );
      
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        debugPrint("⚠️ 사용자가 로그인을 취소했습니다.");
        return;
      }

      debugPrint("📧 계정 선택 완료: ${googleUser.email}");
      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken == null) throw 'Google ID Token을 가져오지 못했습니다.';

      debugPrint("🔗 Supabase 인증 시도 중 (ID Token)...");
      await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
      debugPrint("✅ 네이티브 로그인 성공!");
    } catch (e) {
      debugPrint("❌ 네이티브 로그인 실패: $e");
      debugPrint("🔄 브라우저 기반 OAuth 방식으로 폴백을 시도합니다...");
      
      try {
        await _client.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: dotenv.get('REDIRECT_URL'),
          authScreenLaunchMode: LaunchMode.inAppBrowserView,
        );
      } catch (fallbackError) {
        debugPrint("❌ 최종 로그인 실패: $fallbackError");
      }
    }
  }

  static Future<void> signOut() async {
    _isAdmin = false;
    _isMigrationComplete = false;
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();
      if (await googleSignIn.isSignedIn()) await googleSignIn.signOut();
    } catch (e) {}
    await _client.auth.signOut();
  }

  static Future<Map<String, dynamic>?> fetchRemoteProfile() async {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null) return null;
    // 제네릭 타입을 Nullable로 명시 (Map<String, dynamic>?)
    return await _safeRequest<Map<String, dynamic>?>(() async {
      final List<dynamic> profiles = await _client.from('profiles').select().eq('auth_id', currentUser.id).order('created_at', ascending: true);
      if (profiles.isEmpty) return null;
      return profiles.first as Map<String, dynamic>;
    });
  }

  static Future<Map<String, dynamic>?> getUserProfile() async {
    final box = Hive.box(DatabaseService.sessionBoxName);
    final currentUser = _client.auth.currentUser;
    if (box.get('user_nickname') == null) await box.put('user_nickname', '냥냥이${DateTime.now().millisecondsSinceEpoch % 1000}');
    if (!isGoogleLinked || currentUser == null) {
      _isAdmin = false;
      return {'id': stableId, 'nickname': box.get('user_nickname'), 'recommended_level': box.get('recommended_level')};
    }
    final existingProfile = await fetchRemoteProfile();
    if (existingProfile != null) {
      _isAdmin = existingProfile['is_admin'] == true || existingProfile['is_admin'] == 'true';
      return existingProfile;
    }
    final String gName = currentUser.userMetadata?['full_name'] ?? currentUser.userMetadata?['name'] ?? '구글 유저';
    final newProfile = {'id': stableId, 'nickname': gName, 'auth_id': currentUser.id, 'recommended_level': box.get('recommended_level')};
    await _client.from('profiles').upsert(newProfile, onConflict: 'id');
    return newProfile;
  }

  static Future<void> updateLastStudyPath(String level, int dayIndex) async {
    final now = DateTime.now();
    await Hive.box(DatabaseService.sessionBoxName).put('last_study_path', {'level': level, 'day_index': dayIndex, 'updated_at': now.toIso8601String()});
    if (isGoogleLinked) {
      final currentUser = _client.auth.currentUser;
      if (currentUser != null) {
        await _client.from('profiles').update({'last_study_level': level, 'last_study_day': dayIndex, 'last_study_at': now.toIso8601String()}).eq('auth_id', currentUser.id);
      }
    }
  }

  static Future<void> downloadProgressFromServer() async {
    if (!isGoogleLinked) return;
    await _safeRequest(() async {
      final box = Hive.box(DatabaseService.sessionBoxName);
      final wordBox = Hive.box<Word>(DatabaseService.boxName);
      final profile = await fetchRemoteProfile();
      if (profile == null) return;
      final String remoteSid = profile['id'];
      await box.put('stable_user_id', remoteSid);
      await box.put('user_nickname', profile['nickname']);
      await box.put('recommended_level', profile['recommended_level']);

      final logs = await _client.from('study_logs').select().eq('user_id', remoteSid);
      for (var log in logs) {
        if (log['is_todays_perfect'] == true) {
          await box.put('todays_words_completed_${log['study_date']}', true);
        }
      }

      final response = await _client.from('user_progress').select().eq('user_id', remoteSid);
      for (var row in response) {
        final word = wordBox.get('${row['level']}_${row['word_id']}');
        if (word != null) {
          word.is_bookmarked = row['is_bookmarked'] == true;
          word.is_wrong_note = row['is_wrong_note'] == true;
          word.correct_count = row['correct_count'] ?? 0;
          word.incorrect_count = row['incorrect_count'] ?? 0;
          word.srs_stage = row['srs_stage'] ?? 0;
          word.status = row['status'] ?? 'unlearned';
          if (row['next_review_at'] != null) word.next_review_at = DateTime.tryParse(row['next_review_at']);
          await word.save();
        }
      }
    });
  }

  static Future<void> uploadLocalDataToCloud({bool clearFirst = false}) async {
    if (!isGoogleLinked) return;
    await _safeRequest(() async {
      final sid = stableId;
      if (clearFirst) await _client.from('user_progress').delete().eq('user_id', sid);
      final progressWords = Hive.box<Word>(DatabaseService.boxName).values.where((w) => w.status != 'unlearned' || w.is_bookmarked || w.is_wrong_note).toList();
      if (progressWords.isNotEmpty) {
        final List<Map<String, dynamic>> data = progressWords.map((w) => {
          'user_id': sid, 'word_id': w.id, 'level': w.level, 'correct_count': w.correct_count, 'incorrect_count': w.incorrect_count,
          'is_memorized': w.is_memorized, 'is_bookmarked': w.is_bookmarked, 'is_wrong_note': w.is_wrong_note, 'srs_stage': w.srs_stage,
          'status': w.status, 'next_review_at': w.next_review_at?.toIso8601String(),
        }).toList();
        for (var i = 0; i < data.length; i += 500) {
          final end = (i + 500 < data.length) ? i + 500 : data.length;
          await _client.from('user_progress').upsert(data.sublist(i, end), onConflict: 'user_id, word_id');
        }
      }
    });
  }

  static Future<void> upsertWordProgress(Word word) async {
    if (!isGoogleLinked) return; 
    await _safeRequest(() async {
      await _client.from('user_progress').upsert({
        'user_id': stableId, 'word_id': word.id, 'level': word.level,
        'correct_count': word.correct_count, 'incorrect_count': word.incorrect_count,
        'is_memorized': word.is_memorized, 'is_bookmarked': word.is_bookmarked,
        'is_wrong_note': word.is_wrong_note, 'srs_stage': word.srs_stage,
        'status': word.status, 'next_review_at': word.next_review_at?.toIso8601String(),
      }, onConflict: 'user_id, word_id');
    });
  }

  static Future<void> updateStudyLog({int learnedCount = 0, int reviewCount = 0, double? testScore, bool isTodaysPerfect = false}) async {
    if (!isGoogleLinked) return;
    await _safeRequest(() async {
      final String sid = stableId;
      final String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final existing = await _client.from('study_logs').select().eq('user_id', sid).eq('study_date', today).maybeSingle();
      if (existing != null) {
        await _client.from('study_logs').update({
          'learned_count': (existing['learned_count'] ?? 0) + learnedCount,
          'review_count': (existing['review_count'] ?? 0) + reviewCount,
          'is_todays_perfect': isTodaysPerfect || (existing['is_todays_perfect'] ?? false),
          if (testScore != null) 'test_score': testScore,
        }).eq('user_id', sid).eq('study_date', today);
      } else {
        await _client.from('study_logs').insert({
          'user_id': sid, 'study_date': today, 'learned_count': learnedCount,
          'review_count': reviewCount, 'test_score': testScore ?? 0.0, 'is_todays_perfect': isTodaysPerfect
        });
      }
    });
  }

  /// [복구] 마스터 데이터 가져오기
  static Future<List<Word>> fetchAllWords() async {
    return await _safeRequest(() async {
      List<dynamic> allData = [];
      int from = 0;
      const int step = 1000;
      bool hasMore = true;
      while (hasMore) {
        final List<dynamic> response = await _client.from('words_master').select().range(from, from + step - 1).order('id', ascending: true);
        allData.addAll(response);
        if (response.length < step) hasMore = false;
        else from += step;
      }
      return allData.map((json) => Word.fromJson(json)).toList();
    }) ?? [];
  }

  static Future<void> bulkUpsertWords(List<Word> words) async {
    await _safeRequest(() async {
      final List<Map<String, dynamic>> data = words.map((w) => {
        'id': w.id, 'kanji': w.kanji, 'kana': w.kana.isEmpty ? ' ' : w.kana, 
        'meaning': w.meaning.isEmpty ? '뜻 없음' : w.meaning, 'level': w.level, 
        'pronunciation': w.koreanPronunciation, 'example_sentence': w.example_sentence,
      }).toList();
      for (var i = 0; i < data.length; i += 1000) {
        final end = (i + 1000 < data.length) ? i + 1000 : data.length;
        await _client.from('words_master').upsert(data.sublist(i, end), onConflict: 'id');
      }
    });
  }

  static Future<void> updateNickname(String newNickname) async {
    await Hive.box(DatabaseService.sessionBoxName).put('user_nickname', newNickname);
    if (isGoogleLinked) {
      final currentUser = _client.auth.currentUser;
      if (currentUser != null) await _client.from('profiles').update({'nickname': newNickname}).eq('auth_id', currentUser.id);
    }
  }

  static Future<void> resetRecommendedLevel() async {
    await Hive.box(DatabaseService.sessionBoxName).delete('recommended_level');
    if (isGoogleLinked) {
      final currentUser = _client.auth.currentUser;
      if (currentUser != null) {
        await _safeRequest(() async {
          await _client.from('profiles').update({'recommended_level': null}).eq('auth_id', currentUser.id);
        });
      }
    }
  }

  static Future<void> clearAllProgress() async {
    final box = Hive.box(DatabaseService.sessionBoxName);
    await box.delete('last_study_path');
    for (int i = 1; i <= 5; i++) await box.delete('last_day_N$i');
    await box.delete('last_day_히라가나');
    await box.delete('last_day_가타카나');
    
    final allKeys = box.keys.toList();
    for (var key in allKeys) {
      if (key.toString().startsWith('todays_words_') || key.toString().startsWith('level_test_session')) await box.delete(key);
    }

    if (isGoogleLinked) {
      final sid = stableId;
      await _client.from('user_progress').delete().eq('user_id', sid);
      await _client.from('study_logs').delete().eq('user_id', sid);
      final currentUser = _client.auth.currentUser;
      if (currentUser != null) await _client.from('profiles').update({'recommended_level': null, 'last_study_level': null, 'last_study_day': null, 'last_study_at': null}).eq('auth_id', currentUser.id);
    }
  }

  static Future<void> resetWrongAnswers() async {
    try { if (isGoogleLinked) await _client.from('user_progress').update({'incorrect_count': 0, 'is_wrong_note': false}).eq('user_id', stableId); } catch (e) {}
  }

  static Future<Map<String, dynamic>?> getAppConfig() async {
    return await _safeRequest(() async { 
      final data = await _client.from('app_config').select().single();
      return data as Map<String, dynamic>;
    });
  }
}
