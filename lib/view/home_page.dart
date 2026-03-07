import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../view_model/study_view_model.dart';
import '../service/database_service.dart';
import '../service/supabase_service.dart';
import 'level_summary_page.dart';
import 'bookmark_page.dart';
import 'wrong_answer_page.dart';
import 'statistics_page.dart';
import 'word_list_page.dart';
import 'level_test_page.dart';
import 'calendar_page.dart';
import 'alphabet_page.dart';
import 'seasonal_background.dart';
import '../model/word.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _nickname = '냥냥이';
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final profile = await SupabaseService.getUserProfile();
    if (profile != null && mounted) {
      setState(() { _nickname = profile['nickname'] ?? '냥냥이'; });
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
    _loadUserProfile();
  }

  Future<void> _migrateData() async {
    if (!mounted) return;
    showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));
    try {
      final List<String> files = ['hiragana.json', 'katakana.json', 'n1.json', 'n2.json', 'n3.json', 'n4.json', 'n5.json'];
      List<Word> allWords = [];
      for (String file in files) {
        final String content = await rootBundle.loadString('assets/data/$file');
        final Map<String, dynamic> data = json.decode(content);
        final List<dynamic> vocabList = data['vocabulary'];
        for (var item in vocabList) { allWords.add(Word.fromJson(item)); }
      }
      await SupabaseService.bulkUpsertWords(allWords);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✨ 마이그레이션 성공!')));
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
    }
  }

  Color _getThemePointColor(bool isDarkMode, String appTheme) {
    if (isDarkMode) return const Color(0xFF5B86E5);
    int month = DateTime.now().month;
    String target = appTheme;
    if (target == 'auto') {
      if (month >= 3 && month <= 5) target = 'spring';
      else if (month >= 6 && month <= 8) target = 'summer';
      else if (month >= 9 && month <= 11) target = 'autumn';
      else target = 'winter';
    }
    switch (target) {
      case 'spring': return Colors.pinkAccent;
      case 'summer': return Colors.blueAccent;
      case 'autumn': return Colors.orangeAccent;
      case 'winter': default: return Colors.blueGrey;
    }
  }

  List<Color> _getBannerColors(bool isDarkMode, String appTheme) {
    if (isDarkMode) return [const Color(0xFF3F4E4F), const Color(0xFF2C3333)];
    int month = DateTime.now().month;
    String target = appTheme;
    if (target == 'auto') {
      if (month >= 3 && month <= 5) target = 'spring';
      else if (month >= 6 && month <= 8) target = 'summer';
      else if (month >= 9 && month <= 11) target = 'autumn';
      else target = 'winter';
    }
    switch (target) {
      case 'spring': return [const Color(0xFFFFB7C5), const Color(0xFFF08080)];
      case 'summer': return [const Color(0xFF4FC3F7), const Color(0xFF1976D2)];
      case 'autumn': return [const Color(0xFFFBC02D), const Color(0xFFE64A19)];
      case 'winter': default: return [const Color(0xFF90A4AE), const Color(0xFF455A64)];
    }
  }

  @override
  Widget build(BuildContext context) {
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final isCompletedKey = 'todays_words_completed_$todayStr';
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color subTextColor = isDarkMode ? Colors.white70 : Colors.blueGrey;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final bool shouldPop = await _showExitDialog(context, isDarkMode);
        if (shouldPop && context.mounted) SystemNavigator.pop();
      },
      child: ValueListenableBuilder<Box>(
        valueListenable: Hive.box(DatabaseService.sessionBoxName).listenable(keys: ['app_theme', 'master_data_version', 'last_study_path', 'level_test_session', 'recommended_level']),
        builder: (context, box, _) {
          final String appTheme = box.get('app_theme', defaultValue: 'auto');
          final Map<String, dynamic>? lastPath = box.get('last_study_path') != null ? Map<String, dynamic>.from(box.get('last_study_path')) : null;
          final Map<String, dynamic>? testSession = box.get('level_test_session') != null ? Map<String, dynamic>.from(box.get('level_test_session')) : null;
          final String? recommendedLevel = box.get('recommended_level');
          final Color pointColor = _getThemePointColor(isDarkMode, appTheme);
          final List<Color> bannerColors = _getBannerColors(isDarkMode, appTheme);

          return SeasonalBackground(
            isDarkMode: isDarkMode,
            appTheme: appTheme,
            child: Scaffold(
              key: _scaffoldKey,
              backgroundColor: Colors.transparent,
              drawer: SupabaseService.isAdmin
                  ? Drawer(
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          DrawerHeader(
                            decoration: BoxDecoration(color: pointColor),
                            child: const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Icon(Icons.admin_panel_settings, color: Colors.white, size: 40),
                                SizedBox(height: 10),
                                Text('관리자 메뉴', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          ListTile(
                            leading: const Icon(Icons.cloud_upload_rounded, color: Colors.blue),
                            title: const Text('단어 마이그레이션'),
                            subtitle: const Text('로컬 JSON을 Supabase로 업로드합니다.'),
                            onTap: () { Navigator.pop(context); _migrateData(); },
                          ),
                          ListTile(
                            leading: const Icon(Icons.restart_alt_rounded, color: Colors.red),
                            title: const Text('로컬 버전 초기화'),
                            subtitle: const Text('버전을 0.0으로 리셋합니다.'),
                            onTap: () async {
                              Navigator.pop(context);
                              await Hive.box(DatabaseService.sessionBoxName).put('master_data_version', 0.0);
                              if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🧹 초기화 완료'))); }
                            },
                          ),
                          const Divider(),
                          ListTile(
                            leading: const Icon(Icons.info_outline),
                            title: const Text('데이터 버전'),
                            subtitle: Text(box.get('master_data_version', defaultValue: 1.0).toString()),
                          ),
                        ],
                      ),
                    )
                  : null,
              body: SafeArea(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 15, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // [1] Header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onDoubleTap: () { if (SupabaseService.isAdmin) _scaffoldKey.currentState?.openDrawer(); },
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('반가워요, $_nickname님! 👋', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                                    Text('오늘도 즐겁게 일본어 공부해요🐾', style: TextStyle(fontSize: 13, color: subTextColor, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Row(
                              children: [
                                _buildHeaderIcon(Icons.settings_rounded, () async { await Navigator.push(context, MaterialPageRoute(builder: (context) => const StatisticsPage())); _refresh(); }, isDarkMode),
                                const SizedBox(width: 10),
                                _buildHeaderIcon(Icons.calendar_month_rounded, () async { await Navigator.push(context, MaterialPageRoute(builder: (context) => const CalendarPage())); _refresh(); }, isDarkMode),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // [2] Main Banner
                        ValueListenableBuilder(
                          valueListenable: Hive.box(DatabaseService.sessionBoxName).listenable(keys: [isCompletedKey]),
                          builder: (context, box, child) {
                            final bool isCompleted = box.get(isCompletedKey, defaultValue: false);
                            return GestureDetector(
                              onTap: () async {
                                final viewModel = StudyViewModel();
                                final List<Word> todaysWords = await viewModel.loadTodaysWords();
                                if (context.mounted) {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => WordListPage(level: isCompleted ? '오늘의 단어 복습' : '오늘의 단어', initialDayIndex: 0, allDayChunks: [todaysWords]),
                                    ),
                                  );
                                  _refresh();
                                }
                              },
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: isCompleted ? [Colors.grey.shade600, Colors.grey.shade700] : bannerColors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [BoxShadow(color: isCompleted ? Colors.black12 : bannerColors[0].withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))],
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(isCompleted ? '오늘의 학습 완료! ✅' : '오늘의 학습 시작하기 🔥', style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.bold)),
                                          const SizedBox(height: 4),
                                          Text(isCompleted ? "복습으로 실력을 다지세요." : "매일 10개씩 꾸준히 시작하세요.", style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14)),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 48),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),

                        // [3] Dashboard Row
                        Row(
                          children: [
                            // Left Card: Resume Study or Empty State (No more fallback to Bookmark)
                            Expanded(
                              child: lastPath != null
                                  ? _buildDashCard(context, "이어하기", "${lastPath['level']} D-${lastPath['day_index'] + 1}", Icons.history_rounded, pointColor, isDarkMode, () async {
                                      final viewModel = StudyViewModel();
                                      final allChunks = await viewModel.loadLevelWords(lastPath['level']);
                                      if (context.mounted) Navigator.push(context, MaterialPageRoute(builder: (context) => WordListPage(level: lastPath['level'], initialDayIndex: lastPath['day_index'], allDayChunks: allChunks)));
                                    })
                                  : _buildDashCard(context, "기록 없음", "학습을 시작하세요🐾", Icons.hourglass_empty_rounded, Colors.grey, isDarkMode, null),
                            ),
                            const SizedBox(width: 12),
                            // Right Card: Diagnostic Test or Result
                            Expanded(
                              child: recommendedLevel != null
                                  ? _buildDashCard(context, "추천 레벨", "$recommendedLevel 과정", Icons.workspace_premium_rounded, pointColor, isDarkMode, () => Navigator.push(context, MaterialPageRoute(builder: (context) => LevelSummaryPage(level: recommendedLevel))))
                                  : _buildDashCard(context, "진단 테스트", testSession != null ? "문제 이어풀기" : "진단 테스트 풀기", Icons.assignment_turned_in_rounded, Colors.teal, isDarkMode, () {
                                      if (testSession != null) _showResumeTestDialog(context, pointColor, isDarkMode, testSession);
                                      else _showLevelTestGuide(context, pointColor, isDarkMode);
                                    }),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // [4] Basic Training
                        const Text("기초 다지기", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: _buildCategoryCard(context, '히라가나', '기초 1', Icons.font_download_rounded, Colors.teal, () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AlphabetPage(title: '히라가나', level: 11))), isDarkMode)),
                            const SizedBox(width: 12),
                            Expanded(child: _buildCategoryCard(context, '가타카나', '기초 2', Icons.translate_rounded, Colors.indigo, () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AlphabetPage(title: '가타카나', level: 12))), isDarkMode)),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // [5] Level Study
                        const Text("레벨별 학습", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 3,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.4,
                          children: [
                            _buildLevelCard(context, 'N5', '입문', Colors.green, isDarkMode),
                            _buildLevelCard(context, 'N4', '초급', Colors.lightGreen, isDarkMode),
                            _buildLevelCard(context, 'N3', '중급', Colors.blue, isDarkMode),
                            _buildLevelCard(context, 'N2', '상급', Colors.indigo, isDarkMode),
                            _buildLevelCard(context, 'N1', '전문', Colors.purple, isDarkMode),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // [6] My Management
                        const Text("나의 관리", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: _buildCategoryCard(context, '북마크', '중요', Icons.star_rounded, Colors.amber, () => Navigator.push(context, MaterialPageRoute(builder: (context) => const BookmarkPage())), isDarkMode, isTall: true)),
                            const SizedBox(width: 12),
                            Expanded(child: _buildCategoryCard(context, '오답노트', '틀린단어', Icons.error_outline_rounded, Colors.redAccent, () => Navigator.push(context, MaterialPageRoute(builder: (context) => const WrongAnswerPage())), isDarkMode, isTall: true)),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDashCard(BuildContext context, String title, String subtitle, IconData icon, Color color, bool isDarkMode, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: isDarkMode ? [] : [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
          border: Border.all(color: isDarkMode ? Colors.white10 : color.withOpacity(0.15)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
                  Text(subtitle, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLevelCard(BuildContext context, String level, String desc, Color color, bool isDarkMode) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => LevelSummaryPage(level: level))),
      child: Container(
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(18),
          boxShadow: isDarkMode ? [] : [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8)],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(level, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
            Text(desc, style: TextStyle(fontSize: 12, color: isDarkMode ? Colors.white60 : Colors.grey[600], fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryCard(BuildContext context, String title, String subtitle, IconData icon, Color color, VoidCallback onTap, bool isDarkMode, {bool isTall = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: isTall ? 18 : 14, horizontal: 14),
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(20),
          boxShadow: isDarkMode ? [] : [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text(subtitle, style: TextStyle(fontSize: 12, color: isDarkMode ? Colors.white60 : Colors.grey[600])),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderIcon(IconData icon, VoidCallback onTap, bool isDarkMode) {
    return Container(
      width: 44, height: 44,
      decoration: BoxDecoration(color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.8), shape: BoxShape.circle),
      child: IconButton(icon: Icon(icon, color: const Color(0xFF5B86E5), size: 22), onPressed: onTap, padding: EdgeInsets.zero),
    );
  }

  void _showLevelTestGuide(BuildContext context, Color themeColor, bool isDarkMode) {
    showDialog(context: context, builder: (context) => Dialog(backgroundColor: Colors.transparent, child: Container(padding: const EdgeInsets.fromLTRB(24, 32, 24, 24), decoration: BoxDecoration(color: isDarkMode ? const Color(0xFF2D3436) : Colors.white, borderRadius: BorderRadius.circular(32), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 10))]), child: Column(mainAxisSize: MainAxisSize.min, children: [Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: themeColor.withOpacity(0.12), shape: BoxShape.circle), child: Icon(Icons.auto_awesome_rounded, color: themeColor, size: 40)), const SizedBox(height: 24), Text("정밀 실력 진단", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: isDarkMode ? Colors.white : Colors.black87)), const SizedBox(height: 12), Text("JLPT N1~N5 전 범위를 분석하여\n가장 효율적인 학습 레벨을 추천해 드립니다.", textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: isDarkMode ? Colors.white70 : Colors.blueGrey, height: 1.6)), const SizedBox(height: 24), _buildGuideItem(Icons.playlist_add_check_rounded, "총 30개 문항 (레벨별 핵심 단어)", isDarkMode, themeColor), _buildGuideItem(Icons.timer_outlined, "예상 소요 시간: 약 10분", isDarkMode, themeColor), _buildGuideItem(Icons.analytics_outlined, "취약 구간 분석 및 맞춤형 로드맵", isDarkMode, themeColor), const SizedBox(height: 32), Row(children: [Expanded(child: TextButton(onPressed: () => Navigator.pop(context), style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)), child: Text("나중에", style: TextStyle(color: isDarkMode ? Colors.white24 : Colors.grey, fontWeight: FontWeight.bold)))), const SizedBox(width: 12), Expanded(child: ElevatedButton(onPressed: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => const LevelTestPage(shouldResume: false))); }, style: ElevatedButton.styleFrom(backgroundColor: themeColor, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: const Text("테스트 시작", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))))])]))));
  }

  void _showResumeTestDialog(BuildContext context, Color themeColor, bool isDarkMode, Map<String, dynamic> session) {
    final int currentNum = (session['currentIndex'] ?? 0) + 1;
    showDialog(context: context, builder: (context) => Dialog(backgroundColor: Colors.transparent, child: Container(padding: const EdgeInsets.fromLTRB(24, 32, 24, 24), decoration: BoxDecoration(color: isDarkMode ? const Color(0xFF2D3436) : Colors.white, borderRadius: BorderRadius.circular(32), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 10))]), child: Column(mainAxisSize: MainAxisSize.min, children: [Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: themeColor.withOpacity(0.12), shape: BoxShape.circle), child: Icon(Icons.pending_actions_rounded, color: themeColor, size: 40)), const SizedBox(height: 24), Text("테스트 이어하기", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: isDarkMode ? Colors.white : Colors.black87)), const SizedBox(height: 12), Text("이전에 $currentNum번 문제까지 풀었습니다.\n기록을 이어서 진행하시겠습니까?", textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: isDarkMode ? Colors.white70 : Colors.blueGrey, height: 1.6)), const SizedBox(height: 32), Row(children: [Expanded(child: TextButton(onPressed: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => const LevelTestPage(shouldResume: false))); }, style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)), child: Text("새로 시작", style: TextStyle(color: isDarkMode ? Colors.white24 : Colors.grey, fontWeight: FontWeight.bold)))), const SizedBox(width: 12), Expanded(child: ElevatedButton(onPressed: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => const LevelTestPage(shouldResume: true))); }, style: ElevatedButton.styleFrom(backgroundColor: themeColor, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: const Text("이어서 풀기", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))))])]))));
  }

  Widget _buildGuideItem(IconData icon, String text, bool isDarkMode, Color themeColor) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: themeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Icon(icon, size: 18, color: themeColor)), const SizedBox(width: 12), Expanded(child: Text(text, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: isDarkMode ? Colors.white60 : Colors.black87)))]));
  }

  Future<bool> _showExitDialog(BuildContext context, bool isDarkMode) async {
    final sessionBox = Hive.box(DatabaseService.sessionBoxName);
    final String appTheme = sessionBox.get('app_theme', defaultValue: 'auto');
    final Color themeColor = _getThemePointColor(isDarkMode, appTheme);
    return await showDialog<bool>(context: context, builder: (context) => Dialog(backgroundColor: Colors.transparent, insetPadding: const EdgeInsets.symmetric(horizontal: 40), child: Container(padding: const EdgeInsets.fromLTRB(24, 32, 24, 24), decoration: BoxDecoration(color: isDarkMode ? const Color(0xFF2D3436) : Colors.white, borderRadius: BorderRadius.circular(32), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 10))]), child: Column(mainAxisSize: MainAxisSize.min, children: [Container(width: 72, height: 72, decoration: BoxDecoration(color: themeColor.withOpacity(0.12), shape: BoxShape.circle), child: Icon(Icons.pets_rounded, color: themeColor, size: 38)), const SizedBox(height: 24), Text('정말 종료하시겠습니까?', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: isDarkMode ? Colors.white : Colors.black87, letterSpacing: -0.5)), const SizedBox(height: 12), Text('오늘의 학습 열정이 정말 멋져요!\n내일 또 새로운 단어로 만나요🐾', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, height: 1.6, color: isDarkMode ? Colors.white60 : Colors.blueGrey.withOpacity(0.8), fontWeight: FontWeight.w500)), const SizedBox(height: 32), Row(children: [Expanded(child: TextButton(onPressed: () => Navigator.pop(context, false), style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: Text('더 공부하기', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: isDarkMode ? Colors.white38 : Colors.grey[500])))), const SizedBox(width: 12), Expanded(child: ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: themeColor, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: const Text('종료하기', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold))))])])))) ?? false;
  }
}
