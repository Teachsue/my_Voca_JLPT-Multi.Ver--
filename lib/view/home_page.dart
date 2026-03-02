import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final profile = await SupabaseService.getUserProfile();
    if (profile != null && mounted) {
      setState(() {
        _nickname = profile['nickname'] ?? '냥냥이';
      });
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
    _loadUserProfile();
  }

  // 테마에 따른 포인트 색상 결정
  Color _getThemePointColor(bool isDarkMode, String appTheme) {
    if (isDarkMode) return const Color(0xFF5B86E5);
    int month = DateTime.now().month;
    String target = appTheme;
    if (target == 'auto') {
      if (month >= 3 && month <= 5)
        target = 'spring';
      else if (month >= 6 && month <= 8)
        target = 'summer';
      else if (month >= 9 && month <= 11)
        target = 'autumn';
      else
        target = 'winter';
    }
    switch (target) {
      case 'spring':
        return Colors.pinkAccent;
      case 'summer':
        return Colors.blueAccent;
      case 'autumn':
        return Colors.orangeAccent;
      case 'winter':
      default:
        return Colors.blueGrey;
    }
  }

  List<Color> _getBannerColors(bool isDarkMode, String appTheme) {
    if (isDarkMode) return [const Color(0xFF3F4E4F), const Color(0xFF2C3333)];
    int month = DateTime.now().month;
    String target = appTheme;
    if (target == 'auto') {
      if (month >= 3 && month <= 5)
        target = 'spring';
      else if (month >= 6 && month <= 8)
        target = 'summer';
      else if (month >= 9 && month <= 11)
        target = 'autumn';
      else
        target = 'winter';
    }
    switch (target) {
      case 'spring':
        return [const Color(0xFFFFB7C5), const Color(0xFFF08080)];
      case 'summer':
        return [const Color(0xFF4FC3F7), const Color(0xFF1976D2)];
      case 'autumn':
        return [const Color(0xFFFBC02D), const Color(0xFFE64A19)];
      case 'winter':
      default:
        return [const Color(0xFF90A4AE), const Color(0xFF455A64)];
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
        if (shouldPop && context.mounted) {
          SystemNavigator.pop();
        }
      },
      child: ValueListenableBuilder<Box>(
        valueListenable: Hive.box(
          DatabaseService.sessionBoxName,
        ).listenable(keys: ['app_theme']),
        builder: (context, box, _) {
          final String appTheme = box.get('app_theme', defaultValue: 'auto');
          final List<Color> bannerColors = _getBannerColors(
            isDarkMode,
            appTheme,
          );
          final Color pointColor = _getThemePointColor(isDarkMode, appTheme);

          return SeasonalBackground(
            isDarkMode: isDarkMode,
            appTheme: appTheme,
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: SafeArea(
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '반가워요, $_nickname님!',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '매일매일 꾸준히 학습해요! 🐾',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: subTextColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                _buildHeaderIcon(
                                  Icons.settings_rounded,
                                  () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const StatisticsPage(),
                                      ),
                                    );
                                    _refresh();
                                  },
                                  isDarkMode,
                                ),
                                const SizedBox(width: 8),
                                _buildHeaderIcon(
                                  Icons.calendar_month_rounded,
                                  () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const CalendarPage(),
                                      ),
                                    );
                                    _refresh();
                                  },
                                  isDarkMode,
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ValueListenableBuilder(
                          valueListenable: Hive.box(
                            DatabaseService.sessionBoxName,
                          ).listenable(keys: [isCompletedKey]),
                          builder: (context, box, child) {
                            final bool isCompleted = box.get(
                              isCompletedKey,
                              defaultValue: false,
                            );
                            return GestureDetector(
                              onTap: () async {
                                final viewModel = StudyViewModel();
                                final List<Word> todaysWords = await viewModel
                                    .loadTodaysWords();
                                if (context.mounted) {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => WordListPage(
                                        level: isCompleted
                                            ? '오늘의 단어 복습'
                                            : '오늘의 단어',
                                        initialDayIndex: 0,
                                        allDayChunks: [todaysWords],
                                      ),
                                    ),
                                  );
                                  _refresh();
                                }
                              },
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 22,
                                ),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: isCompleted
                                        ? [
                                            Colors.grey.shade600,
                                            Colors.grey.shade700,
                                          ]
                                        : bannerColors,
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: [
                                    BoxShadow(
                                      color: isCompleted
                                          ? Colors.black26
                                          : bannerColors[0].withOpacity(0.3),
                                      blurRadius: 10,
                                      offset: const Offset(0, 5),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            isCompleted
                                                ? '오늘의 학습 완료! ✅'
                                                : '오늘의 학습 시작하기 🔥',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            isCompleted
                                                ? "복습으로 실력을 다지세요."
                                                : "매일 10개씩 꾸준히 시작하세요.",
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(
                                                0.9,
                                              ),
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.2),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.play_arrow_rounded,
                                        color: Colors.white,
                                        size: 32,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        ValueListenableBuilder(
                          valueListenable: Hive.box(
                            DatabaseService.sessionBoxName,
                          ).listenable(keys: ['recommended_level']),
                          builder: (context, box, child) {
                            final String? recommendedLevel = box.get(
                              'recommended_level',
                            );
                            final bool hasResult = recommendedLevel != null;
                            return GestureDetector(
                              onTap: () async {
                                if (hasResult)
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => LevelSummaryPage(
                                        level: recommendedLevel,
                                      ),
                                    ),
                                  );
                                else
                                  _showLevelTestGuide(
                                    context,
                                    pointColor,
                                    isDarkMode,
                                  );
                                _refresh();
                              },
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: isDarkMode
                                      ? Colors.white.withOpacity(0.1)
                                      : (hasResult
                                            ? const Color(0xFFF0F7FF)
                                            : Colors.white),
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: isDarkMode
                                      ? []
                                      : [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(
                                              0.03,
                                            ),
                                            blurRadius: 6,
                                          ),
                                        ],
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      hasResult
                                          ? Icons.workspace_premium_rounded
                                          : Icons.psychology_alt_rounded,
                                      color: hasResult
                                          ? const Color(0xFF5B86E5)
                                          : pointColor,
                                      size: 28,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        hasResult
                                            ? "추천 레벨: $recommendedLevel"
                                            : "내 실력 진단 테스트",
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
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
                          },
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          "기초 다지기",
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: _buildCategoryCard(
                                context,
                                '히라가나',
                                '기초 1',
                                Icons.font_download_rounded,
                                Colors.teal,
                                () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const AlphabetPage(
                                      title: '히라가나',
                                      level: 11,
                                    ),
                                  ),
                                ),
                                isDarkMode,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildCategoryCard(
                                context,
                                '가타카나',
                                '기초 2',
                                Icons.translate_rounded,
                                Colors.indigo,
                                () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const AlphabetPage(
                                      title: '가타카나',
                                      level: 12,
                                    ),
                                  ),
                                ),
                                isDarkMode,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          "레벨별 학습",
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 3,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 10,
                          childAspectRatio: 1.4,
                          children: [
                            _buildLevelCard(
                              context,
                              'N5',
                              '입문',
                              Colors.green,
                              isDarkMode,
                            ),
                            _buildLevelCard(
                              context,
                              'N4',
                              '초급',
                              Colors.lightGreen,
                              isDarkMode,
                            ),
                            _buildLevelCard(
                              context,
                              'N3',
                              '중급',
                              Colors.blue,
                              isDarkMode,
                            ),
                            _buildLevelCard(
                              context,
                              'N2',
                              '상급',
                              Colors.indigo,
                              isDarkMode,
                            ),
                            _buildLevelCard(
                              context,
                              'N1',
                              '전문',
                              Colors.purple,
                              isDarkMode,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          "나의 관리",
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: _buildCategoryCard(
                                context,
                                '북마크',
                                '중요',
                                Icons.star_rounded,
                                Colors.amber,
                                () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const BookmarkPage(),
                                  ),
                                ),
                                isDarkMode,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildCategoryCard(
                                context,
                                '오답노트',
                                '틀린단어',
                                Icons.error_outline_rounded,
                                Colors.redAccent,
                                () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const WrongAnswerPage(),
                                  ),
                                ),
                                isDarkMode,
                              ),
                            ),
                          ],
                        ),
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

  Widget _buildHeaderIcon(IconData icon, VoidCallback onTap, bool isDarkMode) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: isDarkMode
            ? Colors.white.withOpacity(0.1)
            : Colors.white.withOpacity(0.8),
        shape: BoxShape.circle,
        boxShadow: isDarkMode
            ? []
            : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4)],
      ),
      child: IconButton(
        icon: Icon(icon, color: const Color(0xFF5B86E5), size: 20),
        onPressed: onTap,
        padding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildLevelCard(
    BuildContext context,
    String level,
    String desc,
    Color color,
    bool isDarkMode,
  ) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => LevelSummaryPage(level: level)),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: isDarkMode
              ? Colors.white.withOpacity(0.1)
              : Colors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(14),
          boxShadow: isDarkMode
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 6,
                  ),
                ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              level,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            Text(
              desc,
              style: TextStyle(
                fontSize: 11,
                color: isDarkMode ? Colors.white60 : Colors.grey[600],
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryCard(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap,
    bool isDarkMode,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isDarkMode
              ? Colors.white.withOpacity(0.1)
              : Colors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: isDarkMode ? Colors.white60 : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLevelTestGuide(
    BuildContext context,
    Color themeColor,
    bool isDarkMode,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDarkMode ? const Color(0xFF2D3436) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: themeColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                color: themeColor,
                size: 40,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "정밀 실력 진단",
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 22,
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "JLPT N1~N5 전 범위를 분석하여\n가장 효율적인 학습 레벨을 추천해 드립니다.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDarkMode ? Colors.white70 : Colors.blueGrey,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            _buildGuideItem(
              Icons.playlist_add_check_rounded,
              "총 30개 문항 (레벨별 핵심 단어)",
              isDarkMode,
              themeColor,
            ),
            _buildGuideItem(
              Icons.timer_outlined,
              "예상 소요 시간: 약 10분",
              isDarkMode,
              themeColor,
            ),
            _buildGuideItem(
              Icons.analytics_outlined,
              "취약 구간 분석 및 맞춤형 로드맵 제공",
              isDarkMode,
              themeColor,
            ),
          ],
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    "나중에",
                    style: TextStyle(
                      color: isDarkMode ? Colors.white24 : Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const LevelTestPage(),
                      ),
                    );
                    _refresh();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    "테스트 시작",
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

  Widget _buildGuideItem(
    IconData icon,
    String text,
    bool isDarkMode,
    Color themeColor,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: themeColor.withOpacity(0.6)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: isDarkMode ? Colors.white60 : Colors.black54,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _showExitDialog(BuildContext context, bool isDarkMode) async {
    final sessionBox = Hive.box(DatabaseService.sessionBoxName);
    final String appTheme = sessionBox.get('app_theme', defaultValue: 'auto');
    final Color themeColor = _getThemePointColor(isDarkMode, appTheme);

    return await showDialog<bool>(
          context: context,
          builder: (context) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 40),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF2D3436) : Colors.white,
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: themeColor.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.pets_rounded,
                      color: themeColor,
                      size: 38,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '정말 종료하시겠습니까?',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: isDarkMode ? Colors.white : Colors.black87,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '오늘의 학습 열정이 정말 멋져요!\n내일 또 새로운 단어로 만나요🐾',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: isDarkMode
                          ? Colors.white60
                          : Colors.blueGrey.withOpacity(0.8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(
                            '더 공부하기',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: isDarkMode
                                  ? Colors.white38
                                  : Colors.grey[500],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: themeColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            '종료하기',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ) ??
        false;
  }
}
