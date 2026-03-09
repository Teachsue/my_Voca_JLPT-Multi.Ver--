import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../model/word.dart';
import 'database_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';

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

  /// 구글 네이티브 로그인 (idToken 방식)
  /// 이 방식은 브라우저를 열지 않고 안드로이드 시스템의 계정 선택창을 사용하여
  /// 로그인 완료 후 브라우저 창이 남는 현상을 방지합니다.
  static Future<void> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        // 웹 환경에서는 기존 OAuth 방식을 유지하거나 별도 처리가 필요할 수 있습니다.
        await _client.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: dotenv.get('REDIRECT_URL'),
        );
        return;
      }

      // 1. 네이티브 구글 로그인 시도
      final GoogleSignIn googleSignIn = GoogleSignIn(
        serverClientId: dotenv.get('GOOGLE_WEB_CLIENT_ID'),
      );
      
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        debugPrint("⚠️ 구글 로그인 취소됨");
        return;
      }

      final googleAuth = await googleUser.authentication;
      final accessToken = googleAuth.accessToken;
      final idToken = googleAuth.idToken;

      if (idToken == null) {
        throw 'Google Sign In failed: ID Token is null';
      }

      // 2. Supabase에 ID 토큰을 전달하여 인증 완료
      await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
      
      debugPrint("✅ 네이티브 구글 로그인 성공: ${googleUser.email}");
    } catch (e) {
      debugPrint("❌ 구글 로그인 에러 발생: $e");
      
      // 네이티브 로그인 실패 시 기존 브라우저 방식(OAuth)으로 폴백 시도
      try {
        debugPrint("🔄 브라우저 기반 OAuth 방식으로 재시도합니다...");
        await _client.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: kIsWeb ? null : dotenv.get('REDIRECT_URL'),
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
    
    // 네이티브 구글 로그인도 로그아웃 처리
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();
      if (await googleSignIn.isSignedIn()) {
        await googleSignIn.signOut();
      }
    } catch (e) {
      debugPrint("⚠️ 구글 계정 로그아웃 중 에러: $e");
    }

    await _client.auth.signOut();
    debugPrint("🚪 로그아웃 완료 (인증 세션 종료)");
  }

  static Future<void> refreshUser() async {
    try {
      final session = _client.auth.currentSession;
      if (session == null) return;
      if (session.isExpired) {
        debugPrint("🔄 인증 토큰이 만료되어 갱신을 시도합니다...");
        await _client.auth.refreshSession();
      } else {
        await _client.auth.getUser();
      }
    } catch (e) {
      if (e.toString().contains('refresh_token_not_found') || e.toString().contains('Invalid Refresh Token')) {
        debugPrint("⚠️ 리프레시 토큰이 유효하지 않아 로그아웃 처리합니다.");
        await signOut();
      }
    }
  }

  static Future<T?> _safeRequest<T>(Future<T> Function() request) async {
    try {
      await refreshUser();
      return await request();
    } catch (e) {
      if (e is PostgrestException && (e.code == 'pgrst303' || e.message.contains('JWT expired'))) {
        try {
          debugPrint("🔑 토큰 만료 감지, 재갱신 후 다시 시도합니다...");
          await _client.auth.refreshSession();
          return await request();
        } catch (_) { return null; }
      }
      debugPrint("❌ 서버 요청 중 에러가 발생했습니다: $e");
      return null;
    }
  }

  static Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  // --- 프로필 관리 ---

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

  static Future<Map<String, dynamic>?> getUserProfile() async {
    final box = Hive.box(DatabaseService.sessionBoxName);
    final currentUser = _client.auth.currentUser;
    
    if (box.get('user_nickname') == null) {
      await box.put('user_nickname', '냥냥이${DateTime.now().millisecondsSinceEpoch % 1000}');
    }

    if (!isGoogleLinked || currentUser == null) {
      _isAdmin = false;
      return {
        'id': stableId, 
        'nickname': box.get('user_nickname'), 
        'recommended_level': box.get('recommended_level'),
        'is_dark_mode': box.get('dark_mode') == true || box.get('dark_mode').toString() == 'true',
        'app_theme': box.get('app_theme', defaultValue: 'auto'),
        'last_study_path': box.get('last_study_path'),
      };
    }

    final existingProfile = await fetchRemoteProfile();
    if (existingProfile != null) {
      _isAdmin = existingProfile['is_admin'] == true || existingProfile['is_admin'] == 'true';
      
      final String? lastSyncedId = box.get('last_synced_auth_id');
      if (lastSyncedId != currentUser.id) {
        return {
          'id': stableId, 
          'nickname': box.get('user_nickname'), 
          'recommended_level': box.get('recommended_level'),
          'is_dark_mode': box.get('dark_mode') == true || box.get('dark_mode').toString() == 'true',
          'app_theme': box.get('app_theme', defaultValue: 'auto'),
          'last_study_path': box.get('last_study_path'),
        };
      }

      if (existingProfile['last_study_level'] != null) {
        await box.put('last_study_path', {
          'level': existingProfile['last_study_level'],
          'day_index': existingProfile['last_study_day'],
          'updated_at': existingProfile['last_study_at'],
        });
      }
      return existingProfile; 
    }

    final String gName = currentUser.userMetadata?['full_name'] ?? currentUser.userMetadata?['name'] ?? '구글 유저';
    final String initialNickname = gName; 
    await box.put('user_nickname', initialNickname); 
    
    final newProfile = {
      'id': stableId,
      'nickname': initialNickname,
      'auth_id': currentUser.id,
      'recommended_level': box.get('recommended_level'),
      'last_study_level': null,
      'last_study_day': null,
      'last_study_at': null,
    };
    await _client.from('profiles').upsert(newProfile, onConflict: 'id');
    return newProfile;
  }

  static Future<void> updateLastStudyPath(String level, int dayIndex) async {
    final now = DateTime.now();
    final box = Hive.box(DatabaseService.sessionBoxName);
    final path = {
      'level': level,
      'day_index': dayIndex,
      'updated_at': now.toIso8601String(),
    };
    await box.put('last_study_path', path);
    
    if (isGoogleLinked) {
      final currentUser = _client.auth.currentUser;
      if (currentUser != null) {
        _client.from('profiles').update({
          'last_study_level': level,
          'last_study_day': dayIndex,
          'last_study_at': now.toIso8601String(),
        }).eq('auth_id', currentUser.id).then((_) {
          debugPrint("🚀 마지막 학습 경로 서버 저장 완료");
        }).catchError((e) {
          debugPrint("❌ 서버 저장 실패: $e");
        });
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

      if (profile['last_study_level'] != null) {
        await box.put('last_study_path', {
          'level': profile['last_study_level'],
          'day_index': profile['last_study_day'],
          'updated_at': profile['last_study_at'],
        });
      }

      // [수정] 강제 로컬 초기화 루프를 제거했습니다.
      // 서버 데이터를 내려받기 전에 로컬 데이터를 지우면 동기화되지 않은 데이터가 유실될 수 있습니다.
      // 이제 서버 데이터가 존재하는 단어만 덮어쓰는 '병합 동기화' 방식으로 동작합니다.

      final List<dynamic> response = await _client.from('user_progress').select().eq('user_id', remoteSid);
      debugPrint("📥 서버에서 ${response.length}개의 최신 학습 기록 수신 완료.");

      for (var row in response) {
        final String hiveKey = '${row['level']}_${row['word_id']}';
        final word = wordBox.get(hiveKey);
        if (word != null) {
          word.is_bookmarked = (row['is_bookmarked'] == true || row['is_bookmarked']?.toString() == 'true');
          word.is_wrong_note = (row['is_wrong_note'] == true || row['is_wrong_note']?.toString() == 'true');
          word.correct_count = int.tryParse(row['correct_count']?.toString() ?? '0') ?? 0;
          word.incorrect_count = int.tryParse(row['incorrect_count']?.toString() ?? '0') ?? 0;
          word.srs_stage = int.tryParse(row['srs_stage']?.toString() ?? '0') ?? 0;
          word.status = row['status']?.toString() ?? 'unlearned';
          final String? rawDate = row['next_review_at']?.toString();
          word.next_review_at = rawDate != null ? DateTime.tryParse(rawDate) : null;
          await word.save();
        }
      }
      debugPrint("✅ 학습 데이터 병합 완료! (서버에 없는 로컬 데이터 보존)");
    });
  }

  static Future<void> uploadLocalDataToCloud({bool clearFirst = false}) async {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null) return;

    await _safeRequest(() async {
      final box = Hive.box(DatabaseService.sessionBoxName);
      final remoteProfile = await fetchRemoteProfile();
      if (remoteProfile != null) {
        await box.put('stable_user_id', remoteProfile['id']);
      }
      final sid = stableId;

      await _client.from('profiles').upsert({
        'id': sid,
        'nickname': box.get('user_nickname'),
        'auth_id': currentUser.id,
        'recommended_level': box.get('recommended_level'),
      }, onConflict: 'id');

      if (clearFirst) await _client.from('user_progress').delete().eq('user_id', sid);

      final wordBox = Hive.box<Word>(DatabaseService.boxName);
      final progressWords = wordBox.values.where((w) => w.status != 'unlearned' || w.is_bookmarked || w.is_wrong_note).toList();
      
      if (progressWords.isNotEmpty) {
        final List<Map<String, dynamic>> data = progressWords.map((word) => {
          'user_id': sid, 'word_id': word.id, 'level': word.level,
          'correct_count': word.correct_count, 'incorrect_count': word.incorrect_count,
          'is_memorized': word.is_memorized, 'is_bookmarked': word.is_bookmarked,
          'is_wrong_note': word.is_wrong_note, 'srs_stage': word.srs_stage,
          'status': word.status, 'next_review_at': word.next_review_at?.toIso8601String(),
        }).toList();

        for (var i = 0; i < data.length; i += 500) {
          final end = (i + 500 < data.length) ? i + 500 : data.length;
          await _client.from('user_progress').upsert(data.sublist(i, end), onConflict: 'user_id, word_id');
        }
      }
      debugPrint("🚀 서버 데이터 업로드 완료.");
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

  static Future<void> updateStudyLog({int learnedCount = 0, int reviewCount = 0, double? testScore}) async {
    if (!isGoogleLinked) return;
    await _safeRequest(() async {
      final String sid = stableId;
      final String today = DateTime.now().toIso8601String().split('T')[0];
      final existing = await _client.from('study_logs').select().eq('user_id', sid).eq('study_date', today).maybeSingle();
      
      if (existing != null) {
        await _client.from('study_logs').update({
          'learned_count': (int.tryParse(existing['learned_count']?.toString() ?? '0') ?? 0) + learnedCount,
          'review_count': (int.tryParse(existing['review_count']?.toString() ?? '0') ?? 0) + reviewCount,
          if (testScore != null) 'test_score': testScore,
        }).eq('user_id', sid).eq('study_date', today);
      } else {
        await _client.from('study_logs').insert({
          'user_id': sid, 'study_date': today, 'learned_count': learnedCount,
          'review_count': reviewCount, 'test_score': testScore ?? 0.0,
        });
      }
    });
  }

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
      if (currentUser != null) {
        await _safeRequest(() async {
          await _client.from('profiles').update({'nickname': newNickname}).eq('auth_id', currentUser.id);
        });
      }
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
    
    // 1. 로컬 이어하기 정보 삭제
    await box.delete('last_study_path');
    for (int i = 1; i <= 5; i++) {
      await box.delete('last_day_N$i');
    }
    await box.delete('last_day_히라가나');
    await box.delete('last_day_가타카나');

    if (isGoogleLinked) {
      await _safeRequest(() async {
        final sid = stableId;
        // 2. 서버 학습 기록 삭제
        await _client.from('user_progress').delete().eq('user_id', sid);
        await _client.from('study_logs').delete().eq('user_id', sid);
        
        // 3. 서버 프로필의 이어하기 정보 및 추천 레벨 초기화
        final currentUser = _client.auth.currentUser;
        if (currentUser != null) {
          await _client.from('profiles').update({
            'recommended_level': null,
            'last_study_level': null,
            'last_study_day': null,
            'last_study_at': null,
          }).eq('auth_id', currentUser.id);
        }
      });
    }
    debugPrint("🗑️ 모든 학습 기록 및 이어하기 정보가 초기화되었습니다.");
  }

  static Future<void> resetWrongAnswers() async {
    try { if (isGoogleLinked) await _client.from('user_progress').update({'incorrect_count': 0, 'is_wrong_note': false}).eq('user_id', stableId); } catch (e) {}
  }

  static Future<Map<String, dynamic>?> getAppConfig() async {
    return await _safeRequest(() async { return await _client.from('app_config').select().single(); });
  }
}
