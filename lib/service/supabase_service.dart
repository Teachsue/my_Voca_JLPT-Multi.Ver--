import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../model/word.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class SupabaseService {
  static final SupabaseClient _client = Supabase.instance.client;

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

  // 2. 구글 계정 연동
  static Future<bool> linkWithGoogle() async {
    try {
      final redirectUrl = dotenv.get('REDIRECT_URL');
      
      await _client.auth.linkIdentity(
        OAuthProvider.google,
        redirectTo: redirectUrl,
      );
      
      debugPrint("✅ 구글 계정 연동 프로세스 시작...");
      return true;
    } catch (e) {
      if (e.toString().contains('identity_already_exists')) {
        debugPrint("⚠️ 이미 연동된 구글 계정입니다. 일반 로그인을 시도합니다.");
        try {
          final redirectUrl = dotenv.get('REDIRECT_URL');
          await _client.auth.signInWithOAuth(
            OAuthProvider.google,
            redirectTo: redirectUrl,
          );
          return true;
        } catch (signInError) {
          debugPrint("❌ 일반 로그인 전환 실패: $signInError");
        }
      }
      
      debugPrint("❌ 구글 계정 연동 실패: $e");
      return false;
    }
  }

  // 3. 로그아웃
  static Future<void> signOut() async {
    await _client.auth.signOut();
    await signInAnonymously();
  }

  // --- 프로필 관리 ---

  static Future<Map<String, dynamic>?> getUserProfile() async {
    final currentUserId = userId;
    if (currentUserId == null) return {'nickname': '새로운 냥이'};

    try {
      final response = await _client.from('profiles').select().eq('id', currentUserId).maybeSingle();
      
      if (response == null) {
        try {
          final newProfile = {'id': currentUserId, 'nickname': '새로운 냥이'};
          await Future.delayed(const Duration(milliseconds: 500)); 
          await _client.from('profiles').upsert(newProfile);
          return newProfile;
        } catch (insertError) {
          debugPrint("⚠️ 프로필 자동 생성 실패 (대기 중): $insertError");
          return {'nickname': '새로운 냥이'};
        }
      }
      return response;
    } catch (e) {
      debugPrint("❌ 프로필 로드 실패: $e");
      return {'nickname': '새로운 냥이'};
    }
  }

  static Future<bool> updateNickname(String newNickname) async {
    final currentUserId = userId;
    if (currentUserId == null) return false;
    try {
      await _client.from('profiles').upsert({
        'id': currentUserId,
        'nickname': newNickname,
        'updated_at': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      debugPrint("❌ 닉네임 수정 실패: $e");
      return false;
    }
  }

  // --- 학습 데이터 관리 ---

  static Future<void> upsertWordProgress(Word word) async {
    if (userId == null) return;
    try {
      await _client.from('user_progress').upsert({
        'user_id': userId,
        'word_id': word.id,
        'level': word.level,
        'correct_count': word.correctCount,
        'incorrect_count': word.incorrectCount,
        'is_memorized': word.isMemorized,
        'is_bookmarked': word.isBookmarked,
        'srs_stage': word.srsStage,
        'next_review_date': word.nextReviewDate?.toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id, word_id');
    } catch (e) {
      debugPrint("❌ 데이터 업로드 실패: $e");
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
}
