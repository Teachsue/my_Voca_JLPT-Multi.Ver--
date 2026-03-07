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
      debugPrint("❌ 구글 로그인 에러 발생: $e");
    }
  }

  static Future<void> signOut() async {
    _isAdmin = false;
    _isMigrationComplete = false;
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

    // 1. [로그인 안 됨] 무조건 로컬 데이터 반환
    if (!isGoogleLinked || currentUser == null) {
      _isAdmin = false;
      return {
        'id': stableId, 
        'nickname': box.get('user_nickname'), 
        'recommended_level': box.get('recommended_level'),
        'is_dark_mode': box.get('dark_mode') == true || box.get('dark_mode').toString() == 'true',
        'app_theme': box.get('app_theme', defaultValue: 'auto'),
      };
    }

    // 2. [로그인 됨] 서버에서 프로필 정보만 '조회'합니다. (로컬 덮어쓰기 절대 금지)
    final existingProfile = await fetchRemoteProfile();
    if (existingProfile != null) {
      _isAdmin = existingProfile['is_admin'] == true || existingProfile['is_admin'] == 'true';
      
      // [중요] 마이그레이션 확인 절차(팝업)를 거치지 않았다면, 
      // UI에는 로컬 데이터를 먼저 보여주어 팝업 선택을 방해하지 않습니다.
      final String? lastSyncedId = box.get('last_synced_auth_id');
      if (lastSyncedId != currentUser.id) {
        return {
          'id': stableId, 
          'nickname': box.get('user_nickname'), 
          'recommended_level': box.get('recommended_level'),
          'is_dark_mode': box.get('dark_mode') == true || box.get('dark_mode').toString() == 'true',
          'app_theme': box.get('app_theme', defaultValue: 'auto'),
        };
      }

      // 이미 동기화가 끝난 계정이라면 서버 데이터를 반환 (이미 동기화 버튼에서 로컬에 썼을 것임)
      return existingProfile; 
    }

    // 3. [신규 유저]
    final String gName = currentUser.userMetadata?['full_name'] ?? currentUser.userMetadata?['name'] ?? '구글 유저';
    final String initialNickname = box.get('user_nickname') ?? gName;
    
    final newProfile = {
      'id': stableId,
      'nickname': initialNickname,
      'auth_id': currentUser.id,
      'recommended_level': box.get('recommended_level'),
      'is_dark_mode': box.get('dark_mode') == true || box.get('dark_mode').toString() == 'true',
      'app_theme': box.get('app_theme', defaultValue: 'auto'),
    };
    await _client.from('profiles').upsert(newProfile, onConflict: 'id');
    return newProfile;
  }

  // --- 학습 진행 관리 ---

  static Future<void> downloadProgressFromServer() async {
    if (!isGoogleLinked) return;
    await _safeRequest(() async {
      final box = Hive.box(DatabaseService.sessionBoxName);
      
      // 1. 서버에서 프로필을 먼저 가져옵니다.
      final profile = await fetchRemoteProfile();
      if (profile == null) {
        debugPrint("⚠️ 서버에 프로필이 없어 다운로드할 데이터가 없습니다.");
        return;
      }

      // 2. [핵심] 현재 기기의 SID를 서버 프로필에 등록된 ID로 강제 변경합니다.
      // 이렇게 해야 여러 기기에서 동일한 계정 데이터로 묶이게 됩니다.
      final String remoteSid = profile['id'];
      await box.put('stable_user_id', remoteSid);
      debugPrint("🆔 기기 ID를 서버 계정 ID($remoteSid)와 동기화했습니다.");

      // 3. 프로필 정보 업데이트
      await box.put('user_nickname', profile['nickname']);
      await box.put('recommended_level', profile['recommended_level']);
      await box.put('dark_mode', profile['is_dark_mode'] == true || profile['is_dark_mode']?.toString() == 'true');
      await box.put('app_theme', profile['app_theme'] ?? 'auto');

      // 4. 변경된 ID로 학습 데이터를 조회합니다.
      final List<dynamic> response = await _client.from('user_progress').select().eq('user_id', remoteSid);
      debugPrint("📥 서버에서 ${response.length}개의 학습 기록을 수신했습니다.");
      
      final wordBox = Hive.box<Word>(DatabaseService.boxName);
      for (var row in response) {
        final String hiveKey = '${row['level']}_${row['word_id']}';
        final word = wordBox.get(hiveKey);
        if (word != null) {
          final int serverCorrect = int.tryParse(row['correct_count']?.toString() ?? '0') ?? 0;
          final bool serverBookmarked = row['is_bookmarked'] == true || row['is_bookmarked']?.toString() == 'true';
          final bool serverWrong = row['is_wrong_note'] == true || row['is_wrong_note']?.toString() == 'true';

          // 북마크와 오답노트는 서버와 로컬 중 하나라도 되어있으면 유지 (OR 조건)
          word.is_bookmarked = word.is_bookmarked || serverBookmarked;
          word.is_wrong_note = word.is_wrong_note || serverWrong;

          // 학습 진도는 더 많이 맞춘 쪽(더 최신 기록)을 우선함
          if (serverCorrect > word.correct_count) {
            word.correct_count = serverCorrect;
            word.incorrect_count = int.tryParse(row['incorrect_count']?.toString() ?? '0') ?? 0;
            word.srs_stage = int.tryParse(row['srs_stage']?.toString() ?? '0') ?? 0;
            word.status = row['status']?.toString() ?? 'unlearned';
            final String? rawDate = row['next_review_at']?.toString();
            word.next_review_at = rawDate != null ? DateTime.tryParse(rawDate) : null;
          }
          await word.save();
        }
      }
      debugPrint("✅ 클라우드 데이터 병합 완료!");
    });
  }

  static Future<void> uploadLocalDataToCloud({bool clearFirst = false}) async {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null) return;

    await _safeRequest(() async {
      final box = Hive.box(DatabaseService.sessionBoxName);

      // 1. 서버에 이미 프로필이 있는지 확인합니다.
      final remoteProfile = await fetchRemoteProfile();
      if (remoteProfile != null) {
        // 이미 서버에 데이터가 있다면 그 ID(SID)를 사용해야 충돌이 없습니다.
        final String remoteSid = remoteProfile['id'];
        await box.put('stable_user_id', remoteSid);
        debugPrint("🆔 기존 서버 계정 ID($remoteSid)를 사용하여 업로드합니다.");
      }

      final sid = stableId; // 위에서 갱신되었다면 remoteSid, 아니라면 현재 sid

      debugPrint("📤 로컬 데이터를 서버로 강제 주입합니다... (clearFirst: $clearFirst)");

      await _client.from('profiles').upsert({
        'id': sid,
        'nickname': box.get('user_nickname'),
        'auth_id': currentUser.id,
        'recommended_level': box.get('recommended_level'),
        'is_dark_mode': box.get('dark_mode') == true || box.get('dark_mode').toString() == 'true',
        'app_theme': box.get('app_theme', defaultValue: 'auto'),
      }, onConflict: 'id');

      if (clearFirst) {
        await _client.from('user_progress').delete().eq('user_id', sid);
      }

      final wordBox = Hive.box<Word>(DatabaseService.boxName);
      final progressWords = wordBox.values.where((w) => 
        w.status != 'unlearned' || w.is_bookmarked || w.is_wrong_note
      ).toList();
      
      if (progressWords.isNotEmpty) {
        final List<Map<String, dynamic>> data = progressWords.map((word) => {
          'user_id': sid,
          'word_id': word.id,
          'level': word.level,
          'correct_count': word.correct_count,
          'incorrect_count': word.incorrect_count,
          'is_memorized': word.is_memorized,
          'is_bookmarked': word.is_bookmarked,
          'is_wrong_note': word.is_wrong_note,
          'srs_stage': word.srs_stage,
          'status': word.status,
          'next_review_at': word.next_review_at?.toIso8601String(),
        }).toList();

        for (var i = 0; i < data.length; i += 500) {
          final end = (i + 500 < data.length) ? i + 500 : data.length;
          await _client.from('user_progress').upsert(data.sublist(i, end), onConflict: 'user_id, word_id');
        }
      }
      debugPrint("🚀 로컬 데이터가 서버를 점령했습니다! 동기화 완료.");
    });
  }

  static Future<void> upsertWordProgress(Word word) async {
    if (!isGoogleLinked) return; 
    await _safeRequest(() async {
      await _client.from('user_progress').upsert({
        'user_id': stableId,
        'word_id': word.id,
        'level': word.level,
        'correct_count': word.correct_count,
        'incorrect_count': word.incorrect_count,
        'is_memorized': word.is_memorized,
        'is_bookmarked': word.is_bookmarked,
        'is_wrong_note': word.is_wrong_note,
        'srs_stage': word.srs_stage,
        'status': word.status,
        'next_review_at': word.next_review_at?.toIso8601String(),
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
          'user_id': sid,
          'study_date': today,
          'learned_count': learnedCount,
          'review_count': reviewCount,
          'test_score': testScore ?? 0.0,
        });
      }
      debugPrint("📅 오늘의 학습 로그가 갱신되었습니다.");
    });
  }

  static Future<List<Word>> fetchAllWords() async {
    return await _safeRequest(() async {
      List<dynamic> allData = [];
      int from = 0;
      const int step = 1000;
      bool hasMore = true;

      debugPrint("📡 서버 마스터 단어 데이터 전체 수신을 시작합니다...");

      while (hasMore) {
        final List<dynamic> response = await _client
            .from('words_master')
            .select()
            .range(from, from + step - 1)
            .order('id', ascending: true);
        
        allData.addAll(response);
        debugPrint("📦 데이터 수신 중... (${allData.length}개 완료)");
        
        if (response.length < step) {
          hasMore = false;
        } else {
          from += step;
        }
      }

      debugPrint("✅ 총 ${allData.length}개의 마스터 단어 데이터를 수신했습니다.");
      return allData.map((json) => Word.fromJson(json)).toList();
    }) ?? [];
  }

  static Future<void> bulkUpsertWords(List<Word> words) async {
    await _safeRequest(() async {
      final List<Map<String, dynamic>> data = words.map((w) => {
        'id': w.id, 
        'kanji': w.kanji, 
        'kana': w.kana.isEmpty ? ' ' : w.kana, 
        'meaning': w.meaning.isEmpty ? '뜻 없음' : w.meaning, 
        'level': w.level, 
        'pronunciation': w.koreanPronunciation, 
        'example_sentence': w.example_sentence,
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
    debugPrint("👤 닉네임이 '$newNickname'(으)로 변경되었습니다.");
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
    debugPrint("🔄 추천 레벨 정보가 초기화되었습니다.");
  }

  static Future<void> clearAllProgress() async {
    if (isGoogleLinked) {
      await _safeRequest(() async {
        await _client.from('user_progress').delete().eq('user_id', stableId);
        await _client.from('study_logs').delete().eq('user_id', stableId);
        final currentUser = _client.auth.currentUser;
        if (currentUser != null) {
          await _client.from('profiles').update({'recommended_level': null}).eq('auth_id', currentUser.id);
        }
      });
    }
    debugPrint("🗑️ 모든 서버 학습 데이터가 삭제되었습니다.");
  }

  static Future<void> resetWrongAnswers() async {
    try {
      if (isGoogleLinked) {
        await _client.from('user_progress').update({'incorrect_count': 0, 'is_wrong_note': false}).eq('user_id', stableId);
      }
    } catch (e) {}
  }

  static Future<Map<String, dynamic>?> getAppConfig() async {
    return await _safeRequest(() async {
      return await _client.from('app_config').select().single();
    });
  }
}
