import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../model/word.dart';
import '../view_model/study_view_model.dart';
import '../service/database_service.dart';

class QuizPage extends StatefulWidget {
  final String level;
  final int questionCount;
  final int? day;
  final List<Word>? initialWords;

  const QuizPage({
    super.key,
    required this.level,
    required this.questionCount,
    this.day,
    this.initialWords,
  });

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  late StudyViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = StudyViewModel();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAndInit());
  }

  void _checkAndInit() async {
    final String levelDigit = widget.level.replaceAll(RegExp(r'[^0-9]'), '');
    final int levelInt = levelDigit.isEmpty ? 0 : int.parse(levelDigit);
    if (widget.day == -1) {
      await _viewModel.loadWords(levelInt, questionCount: widget.questionCount, day: widget.day, initialWords: widget.initialWords);
      if (mounted) setState(() {});
      return;
    }
    final savedSession = _viewModel.getSavedSession(levelInt, widget.day);
    if (savedSession != null) {
      if (!mounted) return;
      final bool? resume = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('이어 풀기', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Text('${widget.day != null ? "DAY ${widget.day}" : widget.level} 퀴즈 기록이 있습니다.\n이어서 푸시겠습니까?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('새로 시작')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('이어 풀기', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
        ),
      );
      if (resume == null) { if (mounted) Navigator.pop(context); return; }
      if (resume == true) _viewModel.resumeSession(savedSession);
      else await _viewModel.loadWords(levelInt, questionCount: widget.questionCount, day: widget.day, initialWords: widget.initialWords);
    } else {
      await _viewModel.loadWords(levelInt, questionCount: widget.questionCount, day: widget.day, initialWords: widget.initialWords);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDarkMode ? Colors.white : Colors.black87;
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final bool isTodaysCompleted = Hive.box(DatabaseService.sessionBoxName).get('todays_words_completed_$todayStr', defaultValue: false);

    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(
            widget.day == 0 ? (isTodaysCompleted ? '오늘의 단어 복습 퀴즈' : '오늘의 단어 퀴즈') : (widget.day != null ? '${widget.level} DAY ${widget.day} 퀴즈' : '${widget.level} 퀴즈'),
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
          ),
          backgroundColor: Colors.transparent,
          foregroundColor: textColor,
          elevation: 0,
          centerTitle: true,
        ),
        body: Consumer<StudyViewModel>(
          builder: (context, viewModel, child) {
            if (viewModel.total == 0) return const Center(child: CircularProgressIndicator(color: Color(0xFF5B86E5)));
            if (viewModel.isFinished) {
              // [최적화] 퀴즈 종료 시 한 번만 서버 동기화 호출
              Future.microtask(() => viewModel.syncProgressToServer());
              return _buildResultView(viewModel, isDarkMode);
            }
            return _buildQuizView(context, viewModel, isDarkMode);
          },
        ),
      ),
    );
  }

  Widget _buildResultView(StudyViewModel viewModel, bool isDarkMode) {
    final bool isPerfect = viewModel.score == viewModel.total;
    final Color textColor = isDarkMode ? Colors.white : Colors.black87;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                Icon(isPerfect ? Icons.workspace_premium_rounded : Icons.fitness_center_rounded, size: 80, color: isPerfect ? Colors.orange : Colors.blueGrey),
                const SizedBox(height: 20),
                Text(isPerfect ? '완벽합니다! 💯' : '아쉬워요! 조금만 더 힘내세요 💪', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: textColor)),
                const SizedBox(height: 12),
                RichText(text: TextSpan(style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: isDarkMode ? Colors.white38 : Colors.grey), children: [TextSpan(text: '${viewModel.score}', style: const TextStyle(color: Colors.redAccent)), TextSpan(text: ' / ${viewModel.total}')])),
                const SizedBox(height: 35),
                if (!isPerfect) ...[
                  Row(children: [Icon(Icons.menu_book_rounded, color: isDarkMode ? Colors.white70 : Colors.blueGrey, size: 20), const SizedBox(width: 8), Text('틀린 단어 확인', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor))]),
                  const SizedBox(height: 16),
                  ...List.generate(viewModel.sessionWords.length, (index) {
                    final word = viewModel.sessionWords[index];
                    final userAnswer = viewModel.userAnswers[index];
                    if (userAnswer == word.meaning || userAnswer == word.kanji || userAnswer == word.kana) return const SizedBox.shrink();
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.redAccent.withOpacity(0.2))),
                      child: Row(children: [const Icon(Icons.cancel_rounded, color: Colors.redAccent, size: 22), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${word.kanji} (${word.kana})', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor)), const SizedBox(height: 6), Text('$userAnswer -> ${word.meaning}', style: const TextStyle(fontSize: 14, color: Colors.redAccent, fontWeight: FontWeight.bold))]))]),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 30),
          child: isPerfect
              ? SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5B86E5),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('학습 완료', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: () => viewModel.restart(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('다시 도전하기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF5B86E5), width: 2),
                          foregroundColor: const Color(0xFF5B86E5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('홈으로 돌아가기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildQuizView(BuildContext context, StudyViewModel viewModel, bool isDarkMode) {
    final bool isLast = viewModel.currentIndex == viewModel.total - 1;
    final word = viewModel.currentWord!;
    final type = viewModel.currentQuizType!;
    final Color textColor = isDarkMode ? Colors.white : Color(0xFF2D3142);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 5),
          child: Column(
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('${viewModel.currentIndex + 1} / ${viewModel.total}', style: TextStyle(color: isDarkMode ? Colors.white38 : Colors.grey[600], fontSize: 13, fontWeight: FontWeight.bold)), Text('정답: ${viewModel.score}', style: const TextStyle(color: Colors.green, fontSize: 13, fontWeight: FontWeight.bold))]),
              const SizedBox(height: 6),
              ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: viewModel.total > 0 ? (viewModel.currentIndex + 1) / viewModel.total : 0, minHeight: 5, backgroundColor: isDarkMode ? Colors.white10 : Colors.grey[200], valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF5B86E5)))),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                Container(
                  constraints: const BoxConstraints(minHeight: 160), // 고정 높이 대신 최소 높이 설정
                  alignment: Alignment.center, 
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16), // 상하 패딩 추가
                  decoration: BoxDecoration(color: isDarkMode ? Colors.white.withOpacity(0.1) : Colors.white, borderRadius: BorderRadius.circular(20)),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (type == QuizType.kanjiToMeaning) ...[
                        Text(viewModel.isAnswered ? word.kana : ' ', style: TextStyle(fontSize: 16, color: isDarkMode ? Colors.white38 : Colors.grey[500])),
                        const SizedBox(height: 4),
                        FittedBox( // 긴 한자/카타카나 대응
                          fit: BoxFit.scaleDown,
                          child: Text(word.kanji, style: TextStyle(fontSize: 44, fontWeight: FontWeight.bold, color: textColor)),
                        ),
                        const SizedBox(height: 8),
                        Opacity(
                          opacity: (widget.day != 0 && word.level >= 1 && word.level <= 3 && !viewModel.isAnswered) ? 0.0 : 1.0,
                          child: Text('[ ${word.koreanPronunciation} ]', style: TextStyle(fontSize: 16, color: viewModel.isAnswered ? const Color(0xFF5B86E5) : (isDarkMode ? Colors.white24 : Colors.blueGrey.withOpacity(0.6)))),
                        ),
                      ] else ...[
                        Text('다음 뜻에 맞는 단어는?', style: TextStyle(fontSize: 14, color: isDarkMode ? Colors.white38 : Colors.blueGrey)),
                        const SizedBox(height: 12),
                        FittedBox( // 긴 뜻 대응
                          fit: BoxFit.scaleDown,
                          child: Text(word.meaning, textAlign: TextAlign.center, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: textColor)),
                        ),
                        const SizedBox(height: 8),
                        if (viewModel.isAnswered) 
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('${word.kanji} (${word.kana}) [${word.koreanPronunciation}]', style: const TextStyle(fontSize: 16, color: Color(0xFF5B86E5), fontWeight: FontWeight.w600)),
                          )
                        else Opacity(
                          opacity: (widget.day != 0 && word.level >= 1 && word.level <= 3) ? 0.0 : 1.0,
                          child: Text('[ ${word.koreanPronunciation} ]', style: TextStyle(fontSize: 14, color: isDarkMode ? Colors.white10 : Colors.blueGrey.withOpacity(0.4))),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                ...viewModel.currentOptionWords.map((optionWord) => _buildOptionButton(viewModel, optionWord, isDarkMode)),
              ],
            ),
          ),
        ),
        if (viewModel.isAnswered) Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 25), child: SizedBox(width: double.infinity, height: 52, child: ElevatedButton(onPressed: viewModel.nextQuestion, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF5B86E5), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: Text(isLast ? '결과 보기' : '다음 문제', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))))),
      ],
    );
  }

  Widget _buildOptionButton(StudyViewModel viewModel, Word optionWord, bool isDarkMode) {
    final type = viewModel.currentQuizType!;
    String buttonDisplayLabel = "";
    bool isCorrect = false;
    switch (type) {
      case QuizType.kanjiToMeaning: buttonDisplayLabel = optionWord.meaning; isCorrect = optionWord.meaning == viewModel.currentWord!.meaning; break;
      case QuizType.meaningToKanji: buttonDisplayLabel = optionWord.kanji; isCorrect = optionWord.kanji == viewModel.currentWord!.kanji; break;
      case QuizType.meaningToKana: buttonDisplayLabel = optionWord.kana; isCorrect = optionWord.kana == viewModel.currentWord!.kana; break;
    }
    bool isSelected = buttonDisplayLabel == viewModel.selectedAnswer;
    bool isAnswered = viewModel.isAnswered;
    Color backgroundColor = isDarkMode ? Colors.white.withOpacity(0.05) : Colors.white;
    Color borderColor = isDarkMode ? Colors.white10 : Colors.grey[200]!;
    Color textColor = isDarkMode ? Colors.white : Colors.black87;
    if (isAnswered) {
      if (isCorrect) { backgroundColor = isDarkMode ? Colors.green.withOpacity(0.2) : Colors.green[50]!; borderColor = Colors.green; textColor = isDarkMode ? Colors.greenAccent : Colors.green[700]!; }
      else if (isSelected) { backgroundColor = isDarkMode ? Colors.red.withOpacity(0.2) : Colors.red[50]!; borderColor = Colors.red; textColor = isDarkMode ? Colors.redAccent : Colors.red[700]!; }
      else textColor = isDarkMode ? Colors.white24 : Colors.grey[400]!;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        height: 72,
        child: OutlinedButton(
          onPressed: isAnswered ? null : () => viewModel.submitAnswer(buttonDisplayLabel),
          style: OutlinedButton.styleFrom(backgroundColor: backgroundColor, side: BorderSide(color: borderColor, width: 2), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), padding: const EdgeInsets.symmetric(horizontal: 16)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(buttonDisplayLabel, textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: (isAnswered && isCorrect) ? FontWeight.bold : FontWeight.w500, color: textColor)), const SizedBox(height: 2), Opacity(opacity: isAnswered ? 1.0 : 0.0, child: Text(type == QuizType.kanjiToMeaning ? '${optionWord.kanji} (${optionWord.kana})' : optionWord.koreanPronunciation, style: TextStyle(fontSize: 11, color: textColor.withOpacity(0.5)), maxLines: 1, overflow: TextOverflow.ellipsis))]),
        ),
      ),
    );
  }
}
