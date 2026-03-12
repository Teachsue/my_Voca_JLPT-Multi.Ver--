import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../model/word.dart';
import '../service/database_service.dart';
import '../service/supabase_service.dart';
import 'quiz_page.dart';

class BookmarkPage extends StatefulWidget {
  const BookmarkPage({super.key});

  @override
  State<BookmarkPage> createState() => _BookmarkPageState();
}

class _BookmarkPageState extends State<BookmarkPage> {
  @override
  void initState() {
    super.initState();
    if (SupabaseService.isGoogleLinked) {
      SupabaseService.downloadProgressFromServer();
    }
  }

  @override
  void dispose() {
    if (SupabaseService.isGoogleLinked) {
      SupabaseService.uploadLocalDataToCloud();
    }
    super.dispose();
  }

  Color _getThemePointColor(bool isDarkMode, String appTheme) {
    int month = DateTime.now().month;
    String target = appTheme;
    if (target == 'auto') {
      if (month >= 3 && month <= 5) target = 'spring';
      else if (month >= 6 && month <= 8) target = 'summer';
      else if (month >= 9 && month <= 11) target = 'autumn';
      else target = 'winter';
    }

    if (isDarkMode) {
      // 다크 모드: 더 차분하고 어두운 톤으로 조정
      switch (target) {
        case 'spring': return const Color(0xFF9575CD); // 딥 라벤더
        case 'summer': return const Color(0xFF64B5F6); // 차분한 블루
        case 'autumn': return const Color(0xFFFB8C00); // 깊은 오렌지
        case 'winter': default: return const Color(0xFF78909C); // 어두운 블루그레이
      }
    }

    switch (target) {
      case 'spring': return Colors.pinkAccent;
      case 'summer': return Colors.blueAccent;
      case 'autumn': return Colors.orangeAccent;
      case 'winter': default: return Colors.blueGrey;
    }
  }

  String _getLevelText(int level) {
    if (level <= 5) return 'N$level';
    if (level == 11) return '기초1';
    if (level == 12) return '기초2';
    return '-';
  }

  @override
  Widget build(BuildContext context) {
    final sessionBox = Hive.box(DatabaseService.sessionBoxName);
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return ValueListenableBuilder<Box>(
      valueListenable: sessionBox.listenable(keys: ['app_theme']),
      builder: (context, sBox, _) {
        final String appTheme = sBox.get('app_theme', defaultValue: 'auto');
        final Color themeColor = _getThemePointColor(isDarkMode, appTheme);
        final Color textColor = isDarkMode ? const Color(0xFFBDBDBD) : Colors.black87; // 텍스트 밝기 추가 하향
        final Color subTextColor = isDarkMode ? Colors.white24 : Colors.grey[600]!;

        return Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: Text('북마크한 단어', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: textColor)),
            backgroundColor: Colors.transparent,
            foregroundColor: textColor,
            elevation: 0,
            centerTitle: true,
          ),
          body: SafeArea(
            child: ValueListenableBuilder(
              valueListenable: Hive.box<Word>(DatabaseService.boxName).listenable(),
              builder: (context, Box<Word> box, _) {
                final bookmarkedWords = box.values.where((w) => w.is_bookmarked).toList();

                if (bookmarkedWords.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: themeColor.withOpacity(0.05),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.star_rounded, size: 60, color: themeColor.withOpacity(0.3)),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            '북마크한 단어가 없어요 🐾',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '학습 중에 별 아이콘을 눌러서\n기억하고 싶은 단어를 추가해 보세요!',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: subTextColor, height: 1.5),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Stack(
                  children: [
                    ListView.separated(
                      padding: const EdgeInsets.fromLTRB(24, 10, 24, 140),
                      itemCount: bookmarkedWords.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 14),
                      itemBuilder: (context, index) {
                        final word = bookmarkedWords[index];

                        return Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white, // 더 어두운 배경
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: isDarkMode ? [] : [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 15, offset: const Offset(0, 6))],
                            border: Border.all(
                              color: isDarkMode ? Colors.white.withOpacity(0.03) : themeColor.withOpacity(0.1),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 순번 추가
                                  Container(
                                    width: 24, height: 24,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(color: themeColor.withOpacity(isDarkMode ? 0.1 : 0.08), shape: BoxShape.circle),
                                    child: Text('${index + 1}', style: TextStyle(color: themeColor.withOpacity(0.6), fontSize: 11, fontWeight: FontWeight.bold)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            // 레벨 배지
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(color: themeColor.withOpacity(isDarkMode ? 0.15 : 0.1), borderRadius: BorderRadius.circular(6)),
                                              child: Text(_getLevelText(word.level), style: TextStyle(color: themeColor, fontSize: 10, fontWeight: FontWeight.w900)),
                                            ),
                                            const SizedBox(width: 10),
                                            Text(word.kanji, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor)),
                                            const SizedBox(width: 8),
                                            Text('[${word.kana}]', style: TextStyle(fontSize: 13, color: subTextColor)),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text('발음: ${word.koreanPronunciation}', style: TextStyle(fontSize: 13, color: themeColor.withOpacity(isDarkMode ? 0.6 : 0.7), fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () async {
                                      word.is_bookmarked = false;
                                      await word.save();
                                      if (SupabaseService.isGoogleLinked) {
                                        await SupabaseService.upsertWordProgress(word);
                                      }
                                    },
                                    child: Icon(Icons.star_rounded, color: Colors.amber.withOpacity(isDarkMode ? 0.6 : 1.0), size: 28),
                                  ),
                                ],
                              ),
                              Divider(height: 24, thickness: 0.5, color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.grey[200]),
                              Text(word.meaning, style: TextStyle(fontSize: 16, color: isDarkMode ? Colors.white60 : Colors.grey[800], height: 1.4)),
                            ],
                          ),
                        );
                      },
                    ),
                    _buildQuizButton(context, isDarkMode, bookmarkedWords, themeColor),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuizButton(BuildContext context, bool isDarkMode, List<Word> words, Color themeColor) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        padding: const EdgeInsets.all(24),
        child: SizedBox(
          width: double.infinity, height: 60,
          child: ElevatedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => QuizPage(level: '북마크 학습', questionCount: words.length, day: -1, initialWords: words))),
            icon: Icon(Icons.play_arrow_rounded, size: 28, color: isDarkMode ? Colors.white70 : Colors.white),
            label: Text('북마크 퀴즈 풀기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDarkMode ? Colors.white70 : Colors.white)),
            style: ElevatedButton.styleFrom(
              // 다크 모드 버튼 색상 대폭 하향 (차분하게)
              backgroundColor: isDarkMode ? themeColor.withOpacity(0.4) : themeColor, 
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: isDarkMode ? BorderSide(color: themeColor.withOpacity(0.2)) : BorderSide.none),
              elevation: isDarkMode ? 0 : 8,
              shadowColor: themeColor.withOpacity(0.2),
            ),
          ),
        ),
      ),
    );
  }
}
