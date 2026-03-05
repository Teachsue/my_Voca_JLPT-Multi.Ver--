import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserProfile();

    // 구글 로그인 상태 변화 감시
    _authSubscription = SupabaseService.authStateChanges.listen((data) async {
      if (data.event == AuthChangeEvent.signedIn &&
          SupabaseService.isGoogleLinked &&
          !SupabaseService.isMigrationComplete) {
        debugPrint("🔔 구글 로그인 성공! 동기화 판단 시작...");

        // [중요] 절대 _loadUserProfile()을 여기서 미리 부르지 않음!
        // 서버에 데이터가 있는지만 조용히 확인
        final remoteProfile = await SupabaseService.fetchRemoteProfile();

        if (mounted) {
          if (remoteProfile != null) {
            // 서버 데이터가 있다면 선택지 제공 (이때 로컬 데이터는 그대로 살아있음)
            _showSyncConflictDialog(context, remoteProfile['id']);
          } else {
            // 신규 유저라면 현재 로컬 정보를 서버로 즉시 업로드
            await _loadUserProfile(); // 프로필 생성
            await SupabaseService.uploadLocalDataToCloud(); // 데이터 업로드
            SupabaseService.isMigrationComplete = true;
            if (mounted) {
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("첫 클라우드 동기화가 완료되었습니다! 🎉")),
              );
            }
          }
        }
      }
    });
  }

  void _showSyncConflictDialog(BuildContext context, String serverSid) {
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF2D3436)
            : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          '동기화 선택',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text('서버에 기존 학습 기록이 있습니다.\n어떤 데이터를 유지할까요?'),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              // [로컬 데이터 유지 시나리오]
              // 1. 기기 ID를 서버의 기존 기록과 연결 (ID 통합)
              await SupabaseService.syncStableIdWithServer(serverSid);

              // 2. 현재 내 폰의 상태(닉네임, 추천 레벨, 모든 단어 진도)를 서버에 강제로 덮어씌움
              await SupabaseService.uploadLocalDataToCloud();

              // 3. UI 갱신 (이미 서버가 로컬과 똑같아졌으므로 안전하게 로드)
              final profile = await SupabaseService.getUserProfile();
              if (profile != null && mounted) {
                setState(() {
                  _nickname = profile['nickname'] ?? '냥냥이';
                });
              }

              SupabaseService.isMigrationComplete = true;
              if (mounted) {
                setState(() {});
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text("현재 기기의 데이터를 서버에 안전하게 보존했습니다. 🎉"),
                  ),
                );
              }
            },
            child: const Text('로컬 데이터 유지'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              // [서버 기록 불러오기 시나리오]
              // 1. 기기 ID를 서버의 기존 기록과 연결 (ID 통합)
              await SupabaseService.syncStableIdWithServer(serverSid);

              // 2. 서버에 있는 모든 정보(프로필, 레벨, 단어 진도)를 내 폰으로 강제 이식 (Overwrite Local)
              await SupabaseService.downloadProgressFromServer();

              // 3. UI 갱신
              final profile = await SupabaseService.getUserProfile();
              if (profile != null && mounted) {
                setState(() {
                  _nickname = profile['nickname'] ?? '냥냥이';
                });
              }

              SupabaseService.isMigrationComplete = true;
              if (mounted) {
                setState(() {});
                messenger.showSnackBar(
                  const SnackBar(content: Text("서버의 소중한 기록들을 모두 불러왔습니다. 📥")),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5B86E5),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('서버 기록 불러오기'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadUserProfile();
    }
  }

  Future<void> _loadUserProfile() async {
    if (!mounted) return;
    setState(() => _isLoadingProfile = true);

    if (SupabaseService.isGoogleLinked) {
      await SupabaseService.refreshUser();
    }

    final profile = await SupabaseService.getUserProfile();

    if (profile != null && mounted) {
      setState(() {
        _nickname = profile['nickname'] ?? '냥냥이';
        _isLoadingProfile = false;
      });
    }
  }

  void _showEditNicknameDialog(bool isDarkMode, Color textColor) {
    final controller = TextEditingController(text: _nickname);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDarkMode ? const Color(0xFF2D3436) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          '닉네임 수정',
          style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: textColor),
          decoration: InputDecoration(
            hintText: "새로운 닉네임을 입력하세요",
            hintStyle: TextStyle(
              color: isDarkMode ? Colors.white38 : Colors.grey,
            ),
            counterText: "",
          ),
          maxLength: 10,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                await SupabaseService.updateNickname(newName);
                if (mounted) {
                  setState(() => _nickname = newName);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("닉네임이 변경되었습니다.")),
                  );
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
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessionBox = Hive.box(DatabaseService.sessionBoxName);
    final wordsBox = Hive.box<Word>(DatabaseService.boxName);

    return ValueListenableBuilder(
      valueListenable: sessionBox.listenable(
        keys: ['dark_mode', 'app_theme', 'recommended_level'],
      ),
      builder: (context, sBox, _) {
        return ValueListenableBuilder(
          valueListenable: wordsBox.listenable(),
          builder: (context, wBox, _) {
            final bool isDarkMode = sBox.get('dark_mode', defaultValue: false);
            final Color textColor = isDarkMode ? Colors.white : Colors.black87;
            final Color subTextColor = isDarkMode
                ? Colors.grey[400]!
                : Colors.grey[600]!;
            final Color cardColor = isDarkMode
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.white;

            final Map<int, Word> uniqueWords = {};
            for (var w in wBox.values) {
              if (!uniqueWords.containsKey(w.id)) {
                uniqueWords[w.id] = w;
              } else {
                if (w.correctCount > uniqueWords[w.id]!.correctCount) {
                  uniqueWords[w.id] = w;
                }
              }
            }

            final dynamic rawRecommendedLevel = sBox.get(
              'recommended_level',
              defaultValue: '기록 없음',
            );
            final String recommendedLevel =
                rawRecommendedLevel?.toString() ?? '기록 없음';

            List<Word> targetWords;
            if (recommendedLevel != '기록 없음') {
              int levelInt = 5;
              if (recommendedLevel.contains('N')) {
                levelInt =
                    int.tryParse(recommendedLevel.replaceAll('N', '')) ?? 5;
              } else if (recommendedLevel.contains('히라가나')) {
                levelInt = 11;
              } else if (recommendedLevel.contains('가타카나')) {
                levelInt = 12;
              }
              targetWords = uniqueWords.values
                  .where((w) => w.level == levelInt)
                  .toList();
            } else {
              targetWords = uniqueWords.values.toList();
            }

            final totalWords = targetWords.length;
            final learnedWords = targetWords
                .where((w) => w.correctCount > 0)
                .length;
            final progress = totalWords > 0
                ? (learnedWords / totalWords) * 100
                : 0.0;

            final now = DateTime.now();
            final reviewWords = uniqueWords.values.where((w) {
              if (w.isWrongNote) return true;
              if (w.nextReviewDate != null && w.nextReviewDate!.isBefore(now))
                return true;
              return false;
            }).length;

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
                foregroundColor: textColor,
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
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: isDarkMode
                              ? []
                              : [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.03),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                        ),
                        child: Row(
                          children: [
                            Stack(
                              children: [
                                CircleAvatar(
                                  radius: 25,
                                  backgroundColor: const Color(
                                    0xFF5B86E5,
                                  ).withValues(alpha: 0.1),
                                  child: Icon(
                                    SupabaseService.isGoogleLinked
                                        ? Icons.person_rounded
                                        : Icons.person_outline_rounded,
                                    color: const Color(0xFF5B86E5),
                                    size: 30,
                                  ),
                                ),
                                if (SupabaseService.isGoogleLinked)
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Image.network(
                                        'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_%22G%22_logo.svg/1200px-Google_%22G%22_logo.svg.png',
                                        height: 14,
                                      ),
                                    ),
                                  ),
                              ],
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
                                  if (SupabaseService.isGoogleLinked)
                                    Text(
                                      SupabaseService.userEmail ?? '구글 계정 연동됨',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF5B86E5),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    )
                                  else
                                    Text(
                                      '로그인하여 데이터를 보호하세요 🐾',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: subTextColor,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => _showEditNicknameDialog(
                                isDarkMode,
                                textColor,
                              ),
                              icon: const Icon(
                                Icons.edit_outlined,
                                color: Color(0xFF5B86E5),
                                size: 22,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),
                      _buildSectionTitle('나의 학습 현황', textColor),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: isDarkMode
                              ? []
                              : [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.03),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                        ),
                        child: Column(
                          children: [
                            _buildStatRow(
                              '추천 레벨',
                              recommendedLevel,
                              Icons.stars_rounded,
                              Colors.purple,
                              textColor,
                            ),
                            Divider(
                              height: 30,
                              color: isDarkMode
                                  ? Colors.white10
                                  : Colors.grey[200],
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
                              color: isDarkMode
                                  ? Colors.white10
                                  : Colors.grey[200],
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
                      ),

                      const SizedBox(height: 32),
                      _buildSectionTitle('데이터 관리', textColor),
                      const SizedBox(height: 12),
                      _buildManagementCard(
                        context,
                        title: SupabaseService.isAnonymous
                            ? '구글 계정 연동하기'
                            : '구글 연동 해제 (로그아웃)',
                        subtitle: SupabaseService.isAnonymous
                            ? '학습 데이터를 클라우드에 안전하게 보관'
                            : '로그아웃해도 기기 데이터는 유지됩니다.',
                        icon: Icons.account_circle_rounded,
                        color: SupabaseService.isAnonymous
                            ? const Color(0xFF5B86E5)
                            : Colors.orange,
                        isDarkMode: isDarkMode,
                        onTap: () async {
                          if (SupabaseService.isAnonymous) {
                            await SupabaseService.signInWithGoogle();
                          } else {
                            _showResetDialog(
                              context,
                              '로그아웃',
                              '정말 로그아웃 하시겠습니까?',
                              () async {
                                await SupabaseService.signOut();
                                _loadUserProfile();
                              },
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildManagementCard(
                        context,
                        title: '레벨 테스트 초기화',
                        subtitle: '추천 레벨 및 테스트 기록 삭제',
                        icon: Icons.refresh_rounded,
                        isDarkMode: isDarkMode,
                        onTap: () => _showResetDialog(
                          context,
                          '레벨 테스트 초기화',
                          '추천 레벨 기록을 삭제하시겠습니까?',
                          () async {
                            await SupabaseService.resetRecommendedLevel();
                            if (mounted) setState(() {});
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildManagementCard(
                        context,
                        title: '모든 학습 기록 초기화',
                        subtitle: '모든 진도율, 실력 진단 및 학습 데이터 삭제',
                        icon: Icons.delete_forever_rounded,
                        color: Colors.redAccent,
                        isDarkMode: isDarkMode,
                        onTap: () => _showResetDialog(
                          context,
                          '모든 학습 기록 초기화',
                          '정말 모든 데이터를 공장 초기화하시겠습니까?\n(추천 레벨 및 모든 학습 기록이 삭제됩니다)',
                          () async {
                            await SupabaseService.clearAllProgress();

                            await sBox.delete('recommended_level');
                            final keys = sBox.keys.where(
                              (k) =>
                                  k.toString().contains('todays_words') ||
                                  k.toString().contains('study_count'),
                            );
                            for (var key in keys) {
                              await sBox.delete(key);
                            }

                            final wBox = Hive.box<Word>(
                              DatabaseService.boxName,
                            );
                            for (var word in wBox.values) {
                              word.correctCount = 0;
                              word.incorrectCount = 0;
                              word.isMemorized = false;
                              word.isBookmarked = false;
                              word.isWrongNote = false;
                              word.srsStage = 0;
                              word.nextReviewDate = null;
                              await word.save();
                            }

                            _loadUserProfile();
                            if (mounted) setState(() {});
                          },
                        ),
                      ),
                      const SizedBox(height: 32),
                      Center(
                        child: ValueListenableBuilder(
                          valueListenable: sBox.listenable(
                            keys: ['master_data_version'],
                          ),
                          builder: (context, box, _) => Text(
                            '데이터 버전: v${box.get('master_data_version', defaultValue: 1.0)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDarkMode
                                  ? Colors.white24
                                  : Colors.grey.withValues(alpha: 0.4),
                            ),
                          ),
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
      },
    );
  }

  Widget _buildSectionTitle(String title, Color color) {
    return Text(
      title,
      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: color),
    );
  }

  Widget _buildStatRow(
    String label,
    String value,
    IconData icon,
    Color color,
    Color textColor,
  ) {
    return Row(
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
          color: isDarkMode
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isDarkMode
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
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

  void _showResetDialog(
    BuildContext context,
    String title,
    String content,
    VoidCallback onConfirm,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF2D3436)
            : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              onConfirm();
              Navigator.pop(context);
            },
            child: const Text(
              '확인',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
