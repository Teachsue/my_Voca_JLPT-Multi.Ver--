import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../model/word.dart';
import '../service/database_service.dart';
import '../service/supabase_service.dart';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage>
    with WidgetsBindingObserver {
  String _nickname = '냥냥이...';
  bool _isLoadingProfile = false;

  double _progress = 0.0;
  int _reviewWords = 0;
  bool _isCalculating = false;

  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserProfile();
    _calculateStats();

    _authSubscription = SupabaseService.authStateChanges.listen((data) async {
      final sessionBox = Hive.box(DatabaseService.sessionBoxName);
      final String? lastSyncedId = sessionBox.get('last_synced_auth_id');
      final currentAuthId = Supabase.instance.client.auth.currentUser?.id;

      if (data.event == AuthChangeEvent.signedIn &&
          SupabaseService.isGoogleLinked) {
        if (currentAuthId != null && currentAuthId != lastSyncedId) {
          debugPrint("🔓 새로운 로그인 계정 확인됨. 동기화 팝업 준비 중...");
          _loadUserProfile();
          Future.delayed(const Duration(milliseconds: 1200), () {
            if (mounted) _showSyncChoiceDialog();
          });
        }
      }
    });
  }

  @override
  void dispose() {
    if (SupabaseService.isGoogleLinked) {
      SupabaseService.uploadLocalDataToCloud();
    }
    _authSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _calculateStats() async {
    if (_isCalculating) return;

    final sessionBox = Hive.box(DatabaseService.sessionBoxName);
    final cachedProgress = sessionBox.get('cached_stat_progress');
    final cachedReview = sessionBox.get('cached_stat_review');
    final lastCalcTime = sessionBox.get('last_stat_calc_time');

    // 마지막 계산 후 1분 이내라면 캐시 사용 (성능 최적화)
    if (lastCalcTime != null) {
      final diff = DateTime.now().difference(
        DateTime.tryParse(lastCalcTime) ?? DateTime(2000),
      );
      if (diff.inMinutes < 1 &&
          cachedProgress != null &&
          cachedReview != null) {
        if (mounted) {
          setState(() {
            _progress = cachedProgress;
            _reviewWords = cachedReview;
            _isCalculating = false;
          });
        }
        return;
      }
    }

    if (mounted) setState(() => _isCalculating = true);

    final wBox = Hive.box<Word>(DatabaseService.boxName);
    if (wBox.isEmpty) {
      if (mounted) {
        setState(() {
          _progress = 0.0;
          _reviewWords = 0;
          _isCalculating = false;
        });
      }
      return;
    }

    // 계산 로직 (비차단 방식으로 개선)
    await Future.delayed(const Duration(milliseconds: 100)); // UI 렌더링 우선 보장

    final Map<int, int> wordCorrectMap = {};
    int wrongCount = 0;

    // 맵 생성을 통한 고속 순회
    final allWords = wBox.values.toList();
    for (var word in allWords) {
      if (!wordCorrectMap.containsKey(word.id) ||
          word.correct_count > wordCorrectMap[word.id]!) {
        wordCorrectMap[word.id] = word.correct_count;
      }
      if (word.is_wrong_note) wrongCount++;
    }

    final learnedCount = wordCorrectMap.values.where((c) => c > 0).length;
    final totalProgress = wordCorrectMap.isEmpty
        ? 0.0
        : (learnedCount / wordCorrectMap.length) * 100;

    // 캐시 저장
    await sessionBox.put('cached_stat_progress', totalProgress);
    await sessionBox.put('cached_stat_review', wrongCount);
    await sessionBox.put(
      'last_stat_calc_time',
      DateTime.now().toIso8601String(),
    );

    if (mounted) {
      setState(() {
        _progress = totalProgress;
        _reviewWords = wrongCount;
        _isCalculating = false;
      });
    }
  }

  Future<void> _loadUserProfile() async {
    if (!mounted) return;
    setState(() => _isLoadingProfile = true);

    if (SupabaseService.isGoogleLinked) await SupabaseService.refreshUser();

    final profile = await SupabaseService.getUserProfile();
    if (profile != null && mounted) {
      setState(() {
        _nickname = profile['nickname'] ?? '냥냥이';
        _isLoadingProfile = false;
      });
    } else if (mounted) {
      setState(() => _isLoadingProfile = false);
    }
  }

  void _showSyncChoiceDialog() {
    if (!mounted) return;
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final currentAuthId = Supabase.instance.client.auth.currentUser?.id;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: isDarkMode ? const Color(0xFF2D3436) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: const Column(
          children: [
            Icon(Icons.cloud_sync_rounded, color: Color(0xFF5B86E5), size: 48),
            SizedBox(height: 16),
            Text(
              '데이터 동기화',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
          ],
        ),
        content: const Text(
          '로그인에 성공했습니다! 🎉\n데이터를 어떻게 관리할까요?\n\n(처음이라면 "현재 기기 데이터 유지"를 추천해요)',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, height: 1.5),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        actions: [
          Column(
            children: [
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    if (currentAuthId != null) {
                      await Hive.box(
                        DatabaseService.sessionBoxName,
                      ).put('last_synced_auth_id', currentAuthId);
                    }
                    await SupabaseService.uploadLocalDataToCloud(
                      clearFirst: true,
                    );
                    SupabaseService.isMigrationComplete = true;
                    if (mounted) {
                      _calculateStats();
                      _loadUserProfile();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5B86E5),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    '현재 기기 데이터 유지 (업로드)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    if (currentAuthId != null) {
                      await Hive.box(
                        DatabaseService.sessionBoxName,
                      ).put('last_synced_auth_id', currentAuthId);
                    }
                    SupabaseService.isMigrationComplete = true;
                    await SupabaseService.downloadProgressFromServer();
                    if (mounted) {
                      _calculateStats();
                      _loadUserProfile();
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                      color: Color(0xFF5B86E5),
                      width: 1.5,
                    ),
                    foregroundColor: const Color(0xFF5B86E5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    '클라우드 데이터 가져오기 (다운로드)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessionBox = Hive.box(DatabaseService.sessionBoxName);
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return ValueListenableBuilder<Box>(
      valueListenable: sessionBox.listenable(
        keys: ['dark_mode', 'app_theme', 'recommended_level'],
      ),
      builder: (context, sBox, _) {
        final Color textColor = isDarkMode ? Colors.white : Colors.black87;
        final Color subTextColor = isDarkMode
            ? Colors.grey[400]!
            : Colors.grey[600]!;
        final Color cardColor = isDarkMode
            ? Colors.white.withOpacity(0.1)
            : Colors.white;
        final String rawRecLevel =
            sBox.get('recommended_level')?.toString() ?? '';
        final String recommendedLevel =
            (rawRecLevel == '' ||
                rawRecLevel == 'null' ||
                rawRecLevel == '기록 없음')
            ? '실력 진단 전'
            : rawRecLevel;

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: Text(
              '설정 및 학습 통계',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: textColor,
              ),
            ),
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle('프로필 관리', textColor),
                  const SizedBox(height: 12),
                  _buildProfileCard(
                    cardColor,
                    isDarkMode,
                    textColor,
                    subTextColor,
                  ),
                  const SizedBox(height: 32),
                  _buildSectionTitle('화면 설정', textColor),
                  const SizedBox(height: 12),
                  _buildThemeCard(
                    cardColor,
                    isDarkMode,
                    textColor,
                    subTextColor,
                    sBox,
                  ),
                  const SizedBox(height: 32),
                  _buildSectionTitle('나의 학습 현황', textColor),
                  const SizedBox(height: 12),
                  _buildStatCard(
                    cardColor,
                    isDarkMode,
                    textColor,
                    recommendedLevel,
                    _progress,
                    _reviewWords,
                  ),
                  const SizedBox(height: 32),
                  _buildSectionTitle('데이터 관리', textColor),
                  const SizedBox(height: 12),
                  _buildDataManagementSection(context, isDarkMode, sBox),
                  const SizedBox(height: 32),
                  _buildSectionTitle('법적 정책 및 정보', textColor),
                  const SizedBox(height: 12),
                  _buildLegalSection(context, isDarkMode),
                  const SizedBox(height: 40),
                  Center(
                    child: Text(
                      '버전 1.0.0',
                      style: TextStyle(fontSize: 12, color: subTextColor),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title, Color color) => Text(
    title,
    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: color),
  );

  Widget _buildProfileCard(
    Color cardColor,
    bool isDarkMode,
    Color textColor,
    Color subTextColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: const Color(0xFF5B86E5).withOpacity(0.1),
            child: const Icon(
              Icons.person_rounded,
              color: Color(0xFF5B86E5),
              size: 30,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isLoadingProfile ? '로딩 중...' : _nickname,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                Text(
                  SupabaseService.isGoogleLinked
                      ? (SupabaseService.userEmail ?? '구글 연동됨')
                      : '로그인하여 데이터를 보호하세요 🐾',
                  style: TextStyle(fontSize: 11, color: subTextColor),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _showEditNicknameDialog(isDarkMode, textColor),
            icon: const Icon(
              Icons.edit_outlined,
              color: Color(0xFF5B86E5),
              size: 22,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeCard(
    Color cardColor,
    bool isDarkMode,
    Color textColor,
    Color subTextColor,
    Box sBox,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          SwitchListTile(
            title: Text(
              '다크 모드',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            subtitle: Text(
              '눈이 편안한 어두운 화면',
              style: TextStyle(fontSize: 12, color: subTextColor),
            ),
            value: isDarkMode,
            activeColor: const Color(0xFF5B86E5),
            onChanged: (val) {
              sBox.put('dark_mode', val);
              if (SupabaseService.isGoogleLinked) {
                SupabaseService.uploadLocalDataToCloud();
              }
            },
            contentPadding: EdgeInsets.zero,
            secondary: Icon(
              isDarkMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
              color: const Color(0xFF5B86E5),
            ),
          ),
          Divider(
            height: 1,
            color: isDarkMode ? Colors.white10 : Colors.grey[200],
          ),
          ListTile(
            title: Text(
              '테마 설정',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            subtitle: Text(
              '계절별 맞춤 테마 적용',
              style: TextStyle(fontSize: 12, color: subTextColor),
            ),
            trailing: PopupMenuButton<String>(
              initialValue: sBox.get('app_theme', defaultValue: 'auto'),
              offset: const Offset(0, 45),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              onSelected: (val) {
                sBox.put('app_theme', val);
                if (SupabaseService.isGoogleLinked) {
                  SupabaseService.uploadLocalDataToCloud();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'auto',
                  child: Text('자동', style: TextStyle(fontSize: 14)),
                ),
                const PopupMenuItem(
                  value: 'spring',
                  child: Text('봄', style: TextStyle(fontSize: 14)),
                ),
                const PopupMenuItem(
                  value: 'summer',
                  child: Text('여름', style: TextStyle(fontSize: 14)),
                ),
                const PopupMenuItem(
                  value: 'autumn',
                  child: Text('가을', style: TextStyle(fontSize: 14)),
                ),
                const PopupMenuItem(
                  value: 'winter',
                  child: Text('겨울', style: TextStyle(fontSize: 14)),
                ),
              ],
              child: Container(
                width: 90,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isDarkMode
                      ? Colors.white.withOpacity(0.05)
                      : Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDarkMode ? Colors.white10 : Colors.grey[300]!,
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _getThemeName(
                        sBox.get('app_theme', defaultValue: 'auto'),
                      ),
                      style: TextStyle(fontSize: 14, color: textColor),
                    ),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: textColor.withOpacity(0.5),
                    ),
                  ],
                ),
              ),
            ),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.palette_rounded,
              color: Color(0xFF5B86E5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    Color cardColor,
    bool isDarkMode,
    Color textColor,
    String recLevel,
    double progress,
    int reviewWords,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          _buildStatRow(
            '추천 레벨',
            recLevel,
            Icons.stars_rounded,
            Colors.purple,
            textColor,
          ),
          Divider(
            height: 30,
            color: isDarkMode ? Colors.white10 : Colors.grey[200],
          ),
          _buildStatRow(
            '전체 진도율',
            '${progress.toStringAsFixed(1)}%',
            Icons.pie_chart_rounded,
            Colors.blue,
            textColor,
          ),
          Divider(
            height: 30,
            color: isDarkMode ? Colors.white10 : Colors.grey[200],
          ),
          _buildStatRow(
            '복습 필요 단어',
            '$reviewWords개',
            Icons.replay_rounded,
            Colors.redAccent,
            textColor,
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(
    String label,
    String value,
    IconData icon,
    Color color,
    Color textColor,
  ) => Row(
    children: [
      Icon(icon, color: color, size: 22),
      const SizedBox(width: 12),
      Text(label, style: TextStyle(fontSize: 15, color: textColor)),
      const Spacer(),
      Text(
        value,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    ],
  );

  Widget _buildDataManagementSection(
    BuildContext context,
    bool isDarkMode,
    Box sBox,
  ) {
    return Column(
      children: [
        _buildManagementCard(
          context,
          title: SupabaseService.isAnonymous ? '구글 계정 연동하기' : '구글 연동 해제 (로그아웃)',
          subtitle: SupabaseService.isAnonymous
              ? '데이터를 클라우드에 보관'
              : '로그아웃해도 기기 데이터는 유지됩니다.',
          icon: Icons.account_circle_rounded,
          color: SupabaseService.isAnonymous
              ? const Color(0xFF5B86E5)
              : Colors.blue,
          isDarkMode: isDarkMode,
          onTap: () async {
            if (SupabaseService.isAnonymous) {
              await SupabaseService.signInWithGoogle();
              if (mounted) {
                _loadUserProfile();
                _calculateStats();
              }
            } else {
              _showResetDialog(context, '로그아웃', '정말 로그아웃 하시겠습니까?', () async {
                await sBox.delete('last_synced_auth_id');
                await SupabaseService.signOut();
                SupabaseService.isMigrationComplete = false;
                if (mounted) {
                  _calculateStats();
                  _loadUserProfile();
                }
              });
            }
          },
        ),
        const SizedBox(height: 12),
        _buildManagementCard(
          context,
          title: '실력 진단 초기화',
          subtitle: '추천 레벨 기록을 삭제합니다.',
          icon: Icons.refresh_rounded,
          color: Colors.orangeAccent,
          isDarkMode: isDarkMode,
          onTap: () => _showResetDialog(
            context,
            '실력 진단 초기화',
            '추천 레벨 기록을 삭제하시겠습니까?\n홈에서 다시 테스트를 진행할 수 있습니다.',
            () async {
              await SupabaseService.resetRecommendedLevel();
              if (mounted) _loadUserProfile();
            },
          ),
        ),
        const SizedBox(height: 12),
        _buildManagementCard(
          context,
          title: '모든 학습 기록 초기화',
          subtitle: '공장 초기화 (복구 불가)',
          icon: Icons.delete_forever_rounded,
          color: Colors.redAccent,
          isDarkMode: isDarkMode,
          onTap: () => _showResetDialog(
            context,
            '모든 학습 기록 초기화',
            '정말 모든 데이터를 삭제하시겠습니까?',
            () async {
              if (!mounted) return;
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => const Center(
                  child: CircularProgressIndicator(color: Color(0xFF5B86E5)),
                ),
              );
              try {
                await SupabaseService.clearAllProgress();
                await sBox.delete('recommended_level');
                await sBox.delete('last_synced_auth_id');

                // 오늘의 단어 고정 데이터 및 캘린더 도장 기록 전체 삭제
                final allKeys = sBox.keys.toList();
                for (var key in allKeys) {
                  final String keyStr = key.toString();
                  if (keyStr.startsWith('todays_words_') ||
                      keyStr.startsWith('level_test_session')) {
                    await sBox.delete(key);
                  }
                }

                for (int i = 1; i <= 12; i++) {
                  await sBox.delete('level_${i}_loaded');
                }
                final wBox = Hive.box<Word>(DatabaseService.boxName);
                final Map<String, Word> updates = {};
                int count = 0;
                for (var key in wBox.keys) {
                  final word = wBox.get(key);
                  if (word != null) {
                    word.correct_count = 0;
                    word.incorrect_count = 0;
                    word.is_memorized = false;
                    word.is_bookmarked = false;
                    word.is_wrong_note = false;
                    word.srs_stage = 0;
                    word.next_review_at = null;
                    word.status = 'unlearned';
                    updates[key.toString()] = word;
                  }
                  count++;
                  if (count % 500 == 0) await Future.delayed(Duration.zero);
                }
                await wBox.putAll(updates);
              } finally {
                if (context.mounted) Navigator.of(context).pop();
                if (mounted) {
                  _calculateStats();
                  _loadUserProfile();
                }
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLegalSection(BuildContext context, bool isDarkMode) {
    return Column(
      children: [
        _buildManagementCard(
          context,
          title: '개인정보 처리방침',
          subtitle: '수집하는 데이터 및 이용 약관 확인',
          icon: Icons.policy_rounded,
          isDarkMode: isDarkMode,
          onTap: () => _showPrivacyPolicyDialog(isDarkMode),
        ),
        const SizedBox(height: 12),
        if (SupabaseService.isGoogleLinked)
          _buildManagementCard(
            context,
            title: '계정 탈퇴',
            subtitle: '클라우드 데이터를 포함한 모든 정보 삭제',
            icon: Icons.person_remove_rounded,
            color: Colors.redAccent,
            isDarkMode: isDarkMode,
            onTap: () => _showResetDialog(
              context,
              '계정 탈퇴',
              '정말 계정을 탈퇴하시겠습니까?\n서버에 저장된 모든 학습 데이터와 인증 계정이 즉시 삭제되며 복구할 수 없습니다.',
              () async {
                if (!mounted) return;
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => const Center(
                    child: CircularProgressIndicator(color: Color(0xFF5B86E5)),
                  ),
                );
                try {
                  await SupabaseService.deleteAccount();
                } finally {
                  if (context.mounted) Navigator.of(context).pop();
                  if (mounted) {
                    _calculateStats();
                    _loadUserProfile();
                  }
                }
              },
            ),
          ),
      ],
    );
  }

  void _showPrivacyPolicyDialog(bool isDarkMode) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDarkMode ? const Color(0xFF2D3436) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          '개인정보 처리방침',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '최종 수정일: 2026년 3월 12일\n',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                _buildPolicyText(
                  '1. 수집하는 개인정보 항목',
                  '냥냥 일본어는 구글 로그인을 통해 사용자의 이메일 주소, 이름, 프로필 사진 및 학습 진도 데이터를 수집합니다.',
                ),
                _buildPolicyText(
                  '2. 개인정보의 수집 및 이용 목적',
                  '수집된 정보는 사용자의 학습 기록을 여러 기기 간에 동기화하고, 개인화된 학습 서비스를 제공하는 목적으로만 사용됩니다.',
                ),
                _buildPolicyText(
                  '3. 개인정보의 보관 및 파기',
                  '사용자의 데이터는 계정 탈퇴 시까지 보관되며, 탈퇴 즉시 서버에서 영구적으로 삭제됩니다. 로컬 기기의 데이터는 앱 삭제 시 함께 삭제됩니다.',
                ),
                _buildPolicyText(
                  '4. 제3자 제공 및 위탁',
                  '사용자의 개인정보를 외부 제3자에게 판매하거나 제공하지 않습니다. 데이터 저장을 위해 Supabase 및 Google 인프라를 사용합니다.',
                ),
                _buildPolicyText(
                  '5. 사용자의 권리',
                  '사용자는 언제든지 앱 내 설정 메뉴를 통해 자신의 데이터를 확인하거나 삭제(계정 탈퇴)할 권리가 있습니다.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              '닫기',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPolicyText(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(content, style: const TextStyle(fontSize: 13, height: 1.5)),
        ],
      ),
    );
  }

  Widget _buildManagementCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    Color? color,
    required bool isDarkMode,
    required VoidCallback onTap,
  }) {
    Color textColor = color ?? (isDarkMode ? Colors.white : Colors.black87);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: color ?? (isDarkMode ? Colors.white70 : Colors.black54),
              size: 24,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDarkMode ? Colors.white38 : Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.grey,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  String _getThemeName(String theme) {
    switch (theme) {
      case 'spring':
        return '봄';
      case 'summer':
        return '여름';
      case 'autumn':
        return '가을';
      case 'winter':
        return '겨울';
      default:
        return '자동';
    }
  }

  void _showResetDialog(
    BuildContext context,
    String title,
    String content,
    FutureOr<void> Function() onConfirm,
  ) {
    if (!mounted) return;
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDarkMode ? const Color(0xFF2D3436) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
            const SizedBox(width: 10),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: Text(content, style: const TextStyle(fontSize: 15)),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              '취소',
              style: TextStyle(
                color: isDarkMode ? Colors.white60 : Colors.grey[600],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await onConfirm();
              if (mounted) {
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: Text('✅ $title 처리가 완료되었습니다.'),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  title.contains('삭제') ||
                      title.contains('초기화') ||
                      title.contains('탈퇴')
                  ? Colors.redAccent
                  : const Color(0xFF5B86E5),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              '확인',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditNicknameDialog(bool isDarkMode, Color textColor) {
    if (!mounted) return;
    final TextEditingController controller = TextEditingController(
      text: _nickname,
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDarkMode ? const Color(0xFF2D3436) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          '닉네임 변경',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 10,
          decoration: InputDecoration(
            hintText: '새로운 닉네임을 입력하세요',
            counterStyle: TextStyle(
              color: isDarkMode ? Colors.white38 : Colors.grey,
            ),
            filled: true,
            fillColor: isDarkMode
                ? Colors.white.withOpacity(0.05)
                : Colors.grey[100],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          style: TextStyle(color: textColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                Navigator.of(context).pop();
                FocusManager.instance.primaryFocus?.unfocus();
                await Future.delayed(const Duration(milliseconds: 400));
                await SupabaseService.updateNickname(newName);
                if (mounted) {
                  setState(() {
                    _nickname = newName;
                  });
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5B86E5),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('변경하기'),
          ),
        ],
      ),
    );
  }
}
