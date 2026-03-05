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

class _StatisticsPageState extends State<StatisticsPage> with WidgetsBindingObserver {
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
        
        debugPrint("🔔 구글 로그인 성공 감지! 데이터 이사 시작...");
        
        // 이사가 시작됨을 즉시 알림 (중복 호출 방지)
        SupabaseService.isMigrationComplete = true;

        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("구글 계정 연동 중... 🐾"), duration: Duration(seconds: 2)),
          );
        }

        await _loadUserProfile();
        await SupabaseService.uploadLocalDataToCloud();    // [우선순위 1] 오프라인 변경사항 서버로 밀어넣기
        await SupabaseService.downloadProgressFromServer(); // [우선순위 2] 서버의 나머지 데이터 가져오기

        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("학습 데이터가 안전하게 보관되었습니다! 🎉")),
          );
        }
      }
    });
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
        title: Text('닉네임 수정', style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: textColor),
          decoration: InputDecoration(
            hintText: "새로운 닉네임을 입력하세요",
            hintStyle: TextStyle(color: isDarkMode ? Colors.white38 : Colors.grey),
            counterText: "",
          ),
          maxLength: 10,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                final errorMsg = await SupabaseService.updateNickname(newName);
                if (errorMsg == null && mounted) {
                  setState(() => _nickname = newName);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("닉네임이 변경되었습니다.")));
                } else if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMsg!)));
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5B86E5),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
      valueListenable: sessionBox.listenable(keys: ['dark_mode', 'app_theme', 'recommended_level']),
      builder: (context, sBox, _) {
        return ValueListenableBuilder(
          valueListenable: wordsBox.listenable(),
          builder: (context, wBox, _) {
            final bool isDarkMode = sBox.get('dark_mode', defaultValue: false);
            final Color textColor = isDarkMode ? Colors.white : Colors.black87;
            final Color subTextColor = isDarkMode ? Colors.grey[400]! : Colors.grey[600]!;
            final Color cardColor = isDarkMode ? Colors.white.withOpacity(0.1) : Colors.white;

            final totalWords = wBox.length;
            final learnedWords = wBox.values.where((w) => w.correctCount > 0).length;
            final progress = totalWords > 0 ? (learnedWords / totalWords) * 100 : 0.0;
            final reviewWords = wBox.values.where((w) => w.incorrectCount > 0).length;
            final recommendedLevel = sBox.get('recommended_level', defaultValue: '기록 없음');

            return Scaffold(
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                title: Text('설정 및 학습 통계', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: textColor)),
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
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: isDarkMode ? [] : [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
                        ),
                        child: Row(
                          children: [
                            Stack(
                              children: [
                                CircleAvatar(
                                  radius: 25,
                                  backgroundColor: const Color(0xFF5B86E5).withOpacity(0.1),
                                  child: Icon(
                                    SupabaseService.isGoogleLinked ? Icons.person_rounded : Icons.person_outline_rounded, 
                                    color: const Color(0xFF5B86E5), 
                                    size: 30
                                  ),
                                ),
                                if (SupabaseService.isGoogleLinked)
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
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
                                  Text(_isLoadingProfile ? '로딩 중...' : _nickname, 
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                                  if (SupabaseService.isGoogleLinked)
                                    Text(SupabaseService.userEmail ?? '구글 계정 연동됨', 
                                      style: TextStyle(fontSize: 11, color: const Color(0xFF5B86E5), fontWeight: FontWeight.w500))
                                  else
                                    Text('로그인하여 데이터를 보호하세요 🐾', 
                                      style: TextStyle(fontSize: 11, color: subTextColor)),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => _showEditNicknameDialog(isDarkMode, textColor),
                              icon: const Icon(Icons.edit_outlined, color: Color(0xFF5B86E5), size: 22),
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
                          boxShadow: isDarkMode ? [] : [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
                        ),
                        child: Column(
                          children: [
                            _buildStatRow('추천 레벨', recommendedLevel, Icons.stars_rounded, Colors.purple, textColor),
                            Divider(height: 30, color: isDarkMode ? Colors.white10 : Colors.grey[200]),
                            _buildStatRow('전체 진도율', '${progress.toStringAsFixed(1)}%', Icons.pie_chart_rounded, Colors.blue, textColor),
                            Divider(height: 30, color: isDarkMode ? Colors.white10 : Colors.grey[200]),
                            _buildStatRow('복습 필요 단어', '$reviewWords개', Icons.replay_rounded, Colors.redAccent, textColor),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 32),
                      _buildSectionTitle('데이터 관리', textColor),
                      const SizedBox(height: 12),
                      _buildManagementCard(
                        context,
                        title: SupabaseService.isAnonymous ? '구글 계정 연동하기' : '구글 연동 해제 (로그아웃)',
                        subtitle: SupabaseService.isAnonymous ? '학습 데이터를 클라우드에 안전하게 보관' : '로그아웃해도 기기 데이터는 유지됩니다.',
                        icon: Icons.account_circle_rounded,
                        color: SupabaseService.isAnonymous ? const Color(0xFF5B86E5) : Colors.orange,
                        isDarkMode: isDarkMode,
                        onTap: () async {
                          if (SupabaseService.isAnonymous) {
                            await SupabaseService.signInWithGoogle();
                          } else {
                            _showResetDialog(context, '로그아웃', '정말 로그아웃 하시겠습니까?', () async {
                              await SupabaseService.signOut();
                              _loadUserProfile();
                            });
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
                        onTap: () => _showResetDialog(context, '레벨 테스트 초기화', '추천 레벨 기록을 삭제하시겠습니까?', () {
                          sBox.delete('recommended_level');
                        }),
                      ),
                      const SizedBox(height: 12),
                      _buildManagementCard(
                        context,
                        title: '모든 학습 기록 초기화',
                        subtitle: '모든 진도율, 실력 진단 및 학습 데이터 삭제',
                        icon: Icons.delete_forever_rounded,
                        color: Colors.redAccent,
                        isDarkMode: isDarkMode,
                        onTap: () => _showResetDialog(context, '모든 학습 기록 초기화', '정말 초기화하시겠습니까?', () async {
                          await SupabaseService.clearAllProgress();
                          final wBox = Hive.box<Word>(DatabaseService.boxName);
                          for (var word in wBox.values) {
                            word.correctCount = 0; word.incorrectCount = 0; word.isMemorized = false; word.isBookmarked = false;
                            word.srsStage = 0; word.nextReviewDate = null;
                            word.save();
                          }
                          _loadUserProfile();
                        }),
                      ),
                      const SizedBox(height: 32),
                      Center(
                        child: ValueListenableBuilder(
                          valueListenable: sBox.listenable(keys: ['master_data_version']),
                          builder: (context, box, _) => Text(
                            '데이터 버전: v${box.get('master_data_version', defaultValue: 1.0)}',
                            style: TextStyle(fontSize: 11, color: isDarkMode ? Colors.white24 : Colors.grey.withOpacity(0.4)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            );
          }
        );
      }
    );
  }

  Widget _buildSectionTitle(String title, Color color) {
    return Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: color));
  }

  Widget _buildStatRow(String label, String value, IconData icon, Color color, Color textColor) {
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(fontSize: 15, color: textColor)),
        const Spacer(),
        Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: textColor)),
      ],
    );
  }

  Widget _buildManagementCard(BuildContext context, {required String title, required String subtitle, required IconData icon, Color? color, required bool isDarkMode, required VoidCallback onTap}) {
    Color textColor = color ?? (isDarkMode ? Colors.white : Colors.black87);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isDarkMode ? [] : [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          children: [
            Icon(icon, color: color ?? (isDarkMode ? Colors.white70 : Colors.black54), size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: textColor)),
                Text(subtitle, style: TextStyle(fontSize: 12, color: isDarkMode ? Colors.white38 : Colors.grey[500])),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }

  void _showResetDialog(BuildContext context, String title, String content, VoidCallback onConfirm) {
    showDialog(context: context, builder: (context) => AlertDialog(
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2D3436) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      content: Text(content),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        TextButton(onPressed: () { onConfirm(); Navigator.pop(context); }, child: const Text('확인', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
      ],
    ));
  }
}
