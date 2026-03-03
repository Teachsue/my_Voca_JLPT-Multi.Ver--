import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../model/word.dart';
import '../service/database_service.dart';
import '../service/supabase_service.dart';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> with WidgetsBindingObserver {
  String _nickname = '새로운 냥이';
  bool _isLoadingProfile = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserProfile();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 브라우저 연동 후 앱으로 돌아왔을 때(Resumed) 상태 체크
    if (state == AppLifecycleState.resumed) {
      _checkLinkingResult();
    }
  }

  Future<void> _checkLinkingResult() async {
    // 약간의 딜레이를 주어 SDK가 딥링크를 처리할 시간을 줌
    await Future.delayed(const Duration(milliseconds: 500));
    await SupabaseService.refreshUser();
    
    if (mounted) {
      if (SupabaseService.isGoogleLinked) {
        _loadUserProfile();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("구글 계정과 연동되었습니다! 🎉")));
      } else {
        // 연동되지 않았는데 에러가 로그에 찍혔던 상황이라면 팝업 표시
        // SDK 내부 에러를 직접 잡기 어려우므로, 연동 시도 후에도 identities가 비어있으면 팝업 시도
        if (SupabaseService.isAnonymous) {
          _showLinkErrorDialog(context, Theme.of(context).brightness == Brightness.dark);
        }
      }
    }
  }

  Future<void> _loadUserProfile() async {
    // 서버에서 최신 유저 정보(identities 등)를 강제로 가져옴
    await SupabaseService.refreshUser();
    
    final profile = await SupabaseService.getUserProfile();
    if (profile != null && mounted) {
      setState(() {
        _nickname = profile['nickname'] ?? '새로운 냥이';
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
            final String currentTheme = sBox.get('app_theme', defaultValue: 'auto');
            final Color textColor = isDarkMode ? Colors.white : Colors.black87;
            final Color subTextColor = isDarkMode ? Colors.grey[400]! : Colors.grey[600]!;
            final Color cardColor = isDarkMode ? Colors.white.withOpacity(0.1) : Colors.white;

            final today = DateTime.now().toString().split(' ')[0];
            final isGoalAchieved = sBox.get('todays_words_completed_$today', defaultValue: false);

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
                      // --- 프로필 관리 섹션 ---
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
                            _buildStatRow('오늘의 목표', isGoalAchieved ? '달성 완료 🔥' : '미달성 (오늘의 단어)', 
                              Icons.check_circle_rounded, isGoalAchieved ? Colors.green : Colors.orange, textColor),
                            Divider(height: 30, color: isDarkMode ? Colors.white10 : Colors.grey[200]),
                            _buildStatRow('전체 진도율', '${progress.toStringAsFixed(1)}%', Icons.pie_chart_rounded, Colors.blue, textColor),
                            Divider(height: 30, color: isDarkMode ? Colors.white10 : Colors.grey[200]),
                            _buildStatRow('복습 필요 단어', '$reviewWords개', Icons.replay_rounded, Colors.redAccent, textColor),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 32),
                      _buildSectionTitle('배경 테마 및 모드 설정', textColor),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: isDarkMode ? [] : [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text('다크 모드', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: textColor)),
                              subtitle: Text('눈이 편안한 밤 테마 적용', style: TextStyle(fontSize: 12, color: subTextColor)),
                              value: isDarkMode,
                              onChanged: (val) => sBox.put('dark_mode', val),
                              activeColor: const Color(0xFF5B86E5),
                            ),
                            Divider(color: isDarkMode ? Colors.white10 : Colors.grey[200]),
                            const SizedBox(height: 12),
                            
                            GestureDetector(
                              onTap: () => sBox.put('app_theme', 'auto'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                decoration: BoxDecoration(
                                  color: currentTheme == 'auto' 
                                    ? const Color(0xFF5B86E5).withOpacity(0.15) 
                                    : (isDarkMode ? Colors.white.withOpacity(0.05) : Colors.grey[50]),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: currentTheme == 'auto' ? const Color(0xFF5B86E5) : Colors.transparent,
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.auto_awesome_rounded, 
                                      size: 20, 
                                      color: currentTheme == 'auto' ? const Color(0xFF5B86E5) : subTextColor
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '자동 (현재 계절에 맞춤)', 
                                            style: TextStyle(
                                              fontSize: 15, 
                                              fontWeight: currentTheme == 'auto' ? FontWeight.bold : FontWeight.w500,
                                              color: currentTheme == 'auto' ? const Color(0xFF5B86E5) : textColor
                                            ),
                                          ),
                                          Text(
                                            '일본의 사계절을 자동으로 반영합니다.',
                                            style: TextStyle(fontSize: 11, color: currentTheme == 'auto' ? const Color(0xFF5B86E5).withOpacity(0.7) : subTextColor),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (currentTheme == 'auto')
                                      const Icon(Icons.check_circle_rounded, color: Color(0xFF5B86E5), size: 22),
                                  ],
                                ),
                              ),
                            ),
                            
                            const SizedBox(height: 20),
                            
                            Padding(
                              padding: const EdgeInsets.only(left: 4, bottom: 10),
                              child: Text('수동 계절 선택', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: subTextColor)),
                            ),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _buildSeasonalChip(context, '봄', 'spring', currentTheme, Colors.pinkAccent, isDarkMode),
                                  const SizedBox(width: 8),
                                  _buildSeasonalChip(context, '여름', 'summer', currentTheme, Colors.blueAccent, isDarkMode),
                                  const SizedBox(width: 8),
                                  _buildSeasonalChip(context, '가을', 'autumn', currentTheme, Colors.orangeAccent, isDarkMode),
                                  const SizedBox(width: 8),
                                  _buildSeasonalChip(context, '겨울', 'winter', currentTheme, Colors.blueGrey, isDarkMode),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),
                      _buildSectionTitle('데이터 관리', textColor),
                      const SizedBox(height: 12),
                      
                      // --- 구글 계정 연동 버튼 ---
                      _buildManagementCard(
                        context,
                        title: SupabaseService.isAnonymous ? '구글 계정 연동하기' : '구글 연동 해제 (로그아웃)',
                        subtitle: SupabaseService.isAnonymous 
                          ? '학습 데이터를 서버에 안전하게 보관' 
                          : '현재 구글 계정에서 로그아웃합니다.',
                        icon: Icons.account_circle_rounded,
                        color: SupabaseService.isAnonymous ? const Color(0xFF5B86E5) : Colors.orange,
                        isDarkMode: isDarkMode,
                        onTap: () async {
                          if (SupabaseService.isAnonymous) {
                            // 연동 시도 (브라우저 열림)
                            await SupabaseService.linkWithGoogle();
                            // 결과는 didChangeAppLifecycleState에서 처리됨
                          } else {
                            _showResetDialog(context, '로그아웃', '정말 로그아웃 하시겠습니까? 데이터는 서버에 보관됩니다.', () async {
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
                        onTap: () => _showResetDialog(context, '모든 학습 기록 초기화', '추천 레벨을 포함한 모든 학습 데이터가 영구적으로 삭제됩니다. 계속하시겠습니까?', () async {
                          debugPrint("🧹 전체 초기화 시작...");
                          
                          // 1. 서버 데이터 삭제 (명시적으로 기다림)
                          await SupabaseService.clearAllProgress();

                          // 2. 로컬 데이터 초기화
                          final wBox = Hive.box<Word>(DatabaseService.boxName);
                          final sBox = Hive.box(DatabaseService.sessionBoxName);
                          
                          Map<dynamic, Word> updatedWords = {};
                          for (var entry in wBox.toMap().entries) {
                            final word = entry.value;
                            word.correctCount = 0;
                            word.incorrectCount = 0;
                            word.isMemorized = false;
                            word.isBookmarked = false;
                            word.srsStage = 0;
                            word.nextReviewDate = null;
                            updatedWords[entry.key] = word;
                          }
                          await wBox.putAll(updatedWords);
                          
                          String currentThemeSetting = sBox.get('app_theme', defaultValue: 'auto');
                          bool currentDarkMode = sBox.get('dark_mode', defaultValue: false);
                          double currentDataVer = sBox.get('master_data_version', defaultValue: 1.0);
                          
                          await sBox.clear(); 
                          await sBox.put('app_theme', currentThemeSetting);
                          await sBox.put('dark_mode', currentDarkMode);
                          await sBox.put('master_data_version', currentDataVer); // 데이터 버전은 유지
                          
                          debugPrint("✅ 로컬 및 서버 초기화 완료");
                        }),
                      ),
                      const SizedBox(height: 32),
                      Center(
                        child: Text(
                          '데이터 버전: v${sBox.get('master_data_version', defaultValue: 1.0).toString()}',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDarkMode ? Colors.white24 : Colors.grey.withOpacity(0.4),
                            fontWeight: FontWeight.w500,
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

  Widget _buildSeasonalChip(BuildContext context, String label, String value, String current, Color color, bool isDarkMode) {
    bool isSelected = current == value;
    final sessionBox = Hive.box(DatabaseService.sessionBoxName);
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) sessionBox.put('app_theme', value);
      },
      selectedColor: color.withOpacity(0.3),
      labelStyle: TextStyle(color: isSelected ? (isDarkMode ? Colors.white : color) : (isDarkMode ? Colors.grey[400] : Colors.black87), fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
      backgroundColor: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.grey[100],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: isSelected ? color : Colors.transparent)),
    );
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: textColor)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: isDarkMode ? Colors.white38 : Colors.grey[500])),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: isDarkMode ? Colors.white24 : Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }

  void _showResetDialog(BuildContext context, String title, String content, VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2D3436) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black)),
        content: Text(content, style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          TextButton(
            onPressed: () {
              onConfirm();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$title 완료되었습니다.')));
            },
            child: const Text('확인', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showLinkErrorDialog(BuildContext context, bool isDarkMode) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDarkMode ? const Color(0xFF2D3436) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('연동 실패', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('해당 구글 계정은 이미 다른 유저와 연동되어 있습니다.\n해당 계정으로 로그인하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await SupabaseService.signInWithGoogle();
              // 로그인 성공 여부는 main.dart의 AuthStateChangeListener나 refreshUser로 감지됨
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5B86E5),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('로그인하기'),
          ),
        ],
      ),
    );
  }
}
