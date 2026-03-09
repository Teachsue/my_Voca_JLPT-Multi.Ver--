import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../model/word.dart';
import '../service/database_service.dart';
import '../service/supabase_service.dart';
import 'quiz_page.dart';

class WordListPage extends StatefulWidget {
  final String level;
  final int initialDayIndex;
  final List<List<Word>> allDayChunks;

  const WordListPage({
    super.key,
    required this.level,
    required this.initialDayIndex,
    required this.allDayChunks,
  });

  @override
  State<WordListPage> createState() => _WordListPageState();
}

class _WordListPageState extends State<WordListPage> {
  late PageController _pageController;
  late int _currentDayIndex;

  @override
  void initState() {
    super.initState();
    _currentDayIndex = widget.initialDayIndex;
    _pageController = PageController(initialPage: widget.initialDayIndex);
    _saveStudyPath();
  }

  void _saveStudyPath() {
    // [수정] 오늘의 단어 모드일 때는 마지막 학습 경로를 저장하지 않음
    if (widget.level.contains('오늘')) return;

    final sessionBox = Hive.box(DatabaseService.sessionBoxName);
    sessionBox.put('last_study_path', {
      'level': widget.level,
      'day_index': _currentDayIndex,
      'updated_at': DateTime.now().toIso8601String(),
    });
    if (SupabaseService.isGoogleLinked) {
      SupabaseService.updateLastStudyPath(widget.level, _currentDayIndex);
    }
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
      switch (target) {
        case 'spring': return const Color(0xFFCE93D8);
        case 'summer': return const Color(0xFF90CAF9);
        case 'autumn': return const Color(0xFFFFCC80);
        default: return const Color(0xFFB0BEC5);
      }
    }
    switch (target) {
      case 'spring': return Colors.pinkAccent;
      case 'summer': return Colors.blueAccent;
      case 'autumn': return Colors.orangeAccent;
      default: return Colors.blueGrey;
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
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final sessionBox = Hive.box(DatabaseService.sessionBoxName);
    final String appTheme = sessionBox.get('app_theme', defaultValue: 'auto');
    final Color themeColor = _getThemePointColor(isDarkMode, appTheme);
    final Color textColor = isDarkMode ? const Color(0xFFE0E0E0) : Colors.black87;

    bool isTodaysMode = widget.level.contains('오늘');

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        // [수정] 오늘의 단어 모드일 때는 - DAY X 표시를 숨김
        title: Text(
          isTodaysMode ? widget.level : '${widget.level} - DAY ${_currentDayIndex + 1}',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: textColor),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: textColor,
        elevation: 0,
        centerTitle: true,
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.allDayChunks.length,
        onPageChanged: (index) {
          setState(() {
            _currentDayIndex = index;
          });
          _saveStudyPath();
        },
        itemBuilder: (context, index) {
          final words = widget.allDayChunks[index];
          return _buildWordList(words, isDarkMode, textColor, themeColor);
        },
      ),
      bottomNavigationBar: _buildBottomActionBar(context, isDarkMode, themeColor),
    );
  }

  Widget _buildWordList(List<Word> words, bool isDarkMode, Color textColor, Color themeColor) {
    bool isTodaysMode = widget.level.contains('오늘');
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
      itemCount: words.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final word = words[index];
        final Color subTextColor = isDarkMode ? Colors.white38 : Colors.grey[600]!;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDarkMode ? const Color(0xFF252525) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: isDarkMode ? [] : [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
            border: isDarkMode ? Border.all(color: Colors.white.withOpacity(0.03)) : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // [복구] 순번 표시
              Container(
                width: 22, height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: themeColor.withOpacity(0.1), shape: BoxShape.circle),
                child: Text('${index + 1}', style: TextStyle(color: themeColor.withOpacity(0.7), fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // [수정] 오늘의 단어 모드에서만 난이도 등급 배지 표시
                        if (isTodaysMode) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: themeColor.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                            child: Text(_getLevelText(word.level), style: TextStyle(color: themeColor, fontSize: 10, fontWeight: FontWeight.w900)),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(word.kanji, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                        const SizedBox(width: 8),
                        Text('[${word.kana}]', style: TextStyle(fontSize: 13, color: subTextColor)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('발음: ${word.koreanPronunciation}', style: TextStyle(fontSize: 13, color: themeColor.withOpacity(0.8), fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text(word.meaning, style: TextStyle(fontSize: 15, color: isDarkMode ? Colors.white70 : Colors.grey[800])),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  word.is_bookmarked ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: word.is_bookmarked ? Colors.amber : Colors.grey[400],
                ),
                onPressed: () async {
                  setState(() {
                    word.is_bookmarked = !word.is_bookmarked;
                  });
                  await word.save();
                  if (SupabaseService.isGoogleLinked) {
                    await SupabaseService.upsertWordProgress(word);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomActionBar(BuildContext context, bool isDarkMode, Color themeColor) {
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final isCompletedKey = 'todays_words_completed_$todayStr';
    final sessionBox = Hive.box(DatabaseService.sessionBoxName);
    
    return ValueListenableBuilder(
      valueListenable: sessionBox.listenable(keys: [isCompletedKey]),
      builder: (context, box, _) {
        final bool isCompleted = box.get(isCompletedKey, defaultValue: false);
        bool isTodaysMode = widget.level.contains('오늘');

        return Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Colors.transparent, isDarkMode ? Colors.black.withOpacity(0.2) : Colors.white.withOpacity(0.8)],
            ),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton.icon(
              onPressed: () async {
                // [수정] 오늘의 학습 완료 상태면 메인으로 복귀
                if (isTodaysMode && isCompleted) {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                  return;
                }

                if (mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => QuizPage(
                        level: widget.level,
                        questionCount: widget.allDayChunks[_currentDayIndex].length,
                        day: isTodaysMode ? 0 : _currentDayIndex + 1,
                        initialWords: widget.allDayChunks[_currentDayIndex],
                      ),
                    ),
                  );
                }
              },
              icon: Icon(isTodaysMode && isCompleted ? Icons.check_circle_rounded : Icons.play_arrow_rounded, size: 24),
              label: Text(
                isTodaysMode && isCompleted ? '오늘의 복습 완료!' : '테스트 시작하기!',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: themeColor,
                foregroundColor: isDarkMode ? Colors.black87 : Colors.white,
                elevation: 8,
                shadowColor: themeColor.withOpacity(0.4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            ),
          ),
        );
      }
    );
  }
}
