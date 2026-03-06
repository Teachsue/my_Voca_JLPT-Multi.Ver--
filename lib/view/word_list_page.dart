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
  late bool _isTodaysWords;

  @override
  void initState() {
    super.initState();
    _currentDayIndex = widget.initialDayIndex;
    _pageController = PageController(initialPage: widget.initialDayIndex);
    _isTodaysWords = widget.level == '오늘의 단어' || widget.level == '오늘의 단어 복습';

    if (!_isTodaysWords) {
      final sessionBox = Hive.box(DatabaseService.sessionBoxName);
      sessionBox.put('last_day_${widget.level}', _currentDayIndex + 1);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // 계절 및 모드에 따른 강조 색상을 가져오는 함수
  Color _getThemeColor(bool isDarkMode) {
    final sessionBox = Hive.box(DatabaseService.sessionBoxName);
    final String appTheme = sessionBox.get('app_theme', defaultValue: 'auto');
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
      case 'spring': return const Color(0xFFF08080);
      case 'summer': return const Color(0xFF1976D2);
      case 'autumn': return const Color(0xFFE64A19);
      case 'winter':
      default: return const Color(0xFF455A64);
    }
  }

  @override
  Widget build(BuildContext context) {
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final bool isCompleted = _isTodaysWords && 
        Hive.box(DatabaseService.sessionBoxName).get('todays_words_completed_$todayStr', defaultValue: false);
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDarkMode ? Colors.white : Colors.black87;
    final Color themeColor = _getThemeColor(isDarkMode);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          _isTodaysWords 
              ? (isCompleted ? '오늘의 단어 복습' : '오늘의 단어') 
              : '${widget.level} DAY ${_currentDayIndex + 1}', 
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: textColor)
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: textColor,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.home_rounded, size: 22, color: textColor),
            onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() { _currentDayIndex = index; });
          if (!_isTodaysWords) {
            Hive.box(DatabaseService.sessionBoxName).put('last_day_${widget.level}', index + 1);
          }
        },
        itemCount: widget.allDayChunks.length,
        itemBuilder: (context, chunkIndex) {
          final List<Word> currentWords = widget.allDayChunks[chunkIndex];
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
            itemCount: currentWords.length + (isCompleted ? 1 : 0),
            itemBuilder: (context, index) {
              if (isCompleted && index == 0) return Padding(padding: const EdgeInsets.only(bottom: 20), child: _buildReviewBanner(isDarkMode));
              final wordIndex = isCompleted ? index - 1 : index;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildWordCard(currentWords[wordIndex], wordIndex, isCompleted, isDarkMode, themeColor),
              );
            },
          );
        },
      ),
      bottomNavigationBar: _buildBottomButton(isCompleted, isDarkMode, themeColor),
    );
  }

  Widget _buildReviewBanner(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.lightGreen.withOpacity(0.1) : Colors.lightGreen.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.lightGreen.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline_rounded, color: Colors.lightGreen.shade400),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '학습 완료! 복습 시간입니다.',
              style: TextStyle(fontSize: 14, color: isDarkMode ? Colors.white70 : Colors.black87, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWordCard(Word word, int index, bool isCompleted, bool isDarkMode, Color themeColor) {
    final Color textColor = isDarkMode ? Colors.white : Colors.black87;
    final Color subTextColor = isDarkMode ? Colors.white60 : Colors.grey[600]!;

    return StatefulBuilder(
      builder: (context, setStateItem) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: isDarkMode ? [] : [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8)],
          ),
          child: Row(
            children: [
              Container(
                width: 32, height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: isDarkMode ? Colors.white10 : Colors.grey[100], shape: BoxShape.circle),
                child: Text('${index + 1}', style: TextStyle(color: subTextColor, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          word.kanji,
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
                        ),
                        Text(
                          word.kana,
                          style: TextStyle(fontSize: 13, color: isDarkMode ? Colors.white38 : Colors.grey[400]),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '[ ${word.koreanPronunciation} ]',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDarkMode ? const Color(0xFF5B86E5).withOpacity(0.7) : const Color(0xFF5B86E5).withOpacity(0.6),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      word.meaning,
                      style: TextStyle(fontSize: 15, color: isDarkMode ? Colors.white70 : Colors.grey[700]),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                    word.is_bookmarked
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: word.is_bookmarked
                        ? Colors.amber
                        : (isDarkMode ? Colors.white24 : Colors.grey[300])),
                onPressed: () {
                  setStateItem(() {
                    word.is_bookmarked = !word.is_bookmarked;
                    word.save();
                  });
                  
                  // [최적화] await를 빼서 랙을 없애고, 백그라운드에서 조용히 서버로 전송합니다.
                  if (SupabaseService.isGoogleLinked) {
                    SupabaseService.upsertWordProgress(word);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomButton(bool isCompleted, bool isDarkMode, Color themeColor) {
    final currentWords = widget.allDayChunks[_currentDayIndex];
    return Container(
      padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(context).padding.bottom + 15),
      child: SizedBox(
        width: double.infinity, height: 56,
        child: ElevatedButton.icon(
          onPressed: () {
            if (isCompleted) Navigator.popUntil(context, (route) => route.isFirst);
            else Navigator.push(context, MaterialPageRoute(builder: (context) => QuizPage(level: widget.level, questionCount: currentWords.length, day: _isTodaysWords ? 0 : _currentDayIndex + 1, initialWords: currentWords)));
          },
          icon: Icon(isCompleted ? Icons.check_circle_rounded : Icons.quiz_rounded),
          label: Text(isCompleted ? '복습 완료! ✅' : '퀴즈 풀기', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: isCompleted ? Colors.lightGreen : themeColor, // 테마 색상 적용
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: isDarkMode ? 0 : 4,
          ),
        ),
      ),
    );
  }
}
