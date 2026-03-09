import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../model/word.dart';
import '../view_model/study_view_model.dart';
import '../service/database_service.dart';
import 'seasonal_background.dart';

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

class _QuizPageState extends State<QuizPage> with WidgetsBindingObserver {
  late StudyViewModel _viewModel;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _viewModel = StudyViewModel();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initQuiz();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _saveCurrentSession();
    }
  }

  int _safeParseLevel(String levelName) {
    if (levelName.contains('히라가나')) return 11;
    if (levelName.contains('가타카나')) return 12;
    if (levelName.contains('오답')) return -2;
    if (levelName.contains('북마크')) return -3;
    if (levelName.contains('오늘')) return -4;
    
    final RegExp digitRegExp = RegExp(r'\d+');
    final match = digitRegExp.firstMatch(levelName);
    if (match != null) {
      return int.tryParse(match.group(0)!) ?? 5;
    }
    return 5;
  }

  Future<void> _initQuiz() async {
    final int levelInt = _safeParseLevel(widget.level);
    final int dayInt = widget.day ?? -1;

    // [복구] 이어풀기 세션 확인 (initialWords가 있어도 세션이 있다면 묻기)
    final savedSession = _viewModel.getSavedSession(levelInt, dayInt);
    if (savedSession != null) {
      final bool? resume = await _showResumeDialog();
      if (resume == true) {
        await _viewModel.resumeSession(levelInt, dayInt);
        if (mounted) setState(() => _isInitialized = true);
        return;
      } else {
        await _viewModel.clearSession(levelInt, dayInt);
      }
    }

    // 새로운 퀴즈 로드
    await _viewModel.loadWords(
      levelInt, 
      questionCount: widget.questionCount, 
      day: widget.day, 
      initialWords: widget.initialWords
    );
    
    if (mounted) setState(() => _isInitialized = true);
  }

  Future<bool?> _showResumeDialog() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2D3436) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(children: [Icon(Icons.history_rounded, color: Color(0xFF5B86E5)), SizedBox(width: 10), Text('이어 풀기', style: TextStyle(fontWeight: FontWeight.bold))]),
        content: Text('${widget.day != null && widget.day != 0 ? "DAY ${widget.day}" : widget.level} 퀴즈 기록이 있습니다.\n이어서 푸시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('새로 시작', style: TextStyle(color: Colors.grey))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('이어 풀기', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF5B86E5)))),
        ],
      ),
    );
  }

  void _saveCurrentSession() {
    final int levelInt = _safeParseLevel(widget.level);
    final int dayInt = widget.day ?? -1;
    if (!_viewModel.isFinished) {
      _viewModel.saveSession(levelInt, dayInt);
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

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color textColor = isDarkMode ? const Color(0xFFE0E0E0) : Colors.black87;
    final sessionBox = Hive.box(DatabaseService.sessionBoxName);
    final String appTheme = sessionBox.get('app_theme', defaultValue: 'auto');
    final Color themeColor = _getThemePointColor(isDarkMode, appTheme);

    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: SeasonalBackground(
        isDarkMode: isDarkMode,
        appTheme: appTheme,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: Text(widget.level, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
            backgroundColor: Colors.transparent,
            foregroundColor: textColor,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () {
                _saveCurrentSession();
                Navigator.pop(context);
              },
            ),
            actions: [
              Consumer<StudyViewModel>(
                builder: (_, vm, __) {
                  final displayIdx = (vm.currentIndex + 1).clamp(1, vm.total > 0 ? vm.total : 1);
                  return Padding(
                    padding: const EdgeInsets.only(right: 20),
                    child: Center(child: Text('$displayIdx / ${vm.total}', style: TextStyle(color: textColor.withOpacity(0.5), fontWeight: FontWeight.w800))),
                  );
                },
              )
            ],
          ),
          body: Consumer<StudyViewModel>(
            builder: (context, viewModel, child) {
              if (!_isInitialized || (viewModel.total == 0 && !viewModel.isFinished)) {
                return const Center(child: CircularProgressIndicator(color: Color(0xFF5B86E5)));
              }
              if (viewModel.isFinished) {
                if (widget.day == 0 && viewModel.score == viewModel.total) {
                  final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
                  Hive.box(DatabaseService.sessionBoxName).put('todays_words_completed_$todayStr', true);
                }
                Future.microtask(() => viewModel.syncProgressToServer());
                return _buildResultView(viewModel, isDarkMode, themeColor);
              }
              return _buildQuizView(context, viewModel, isDarkMode, textColor, themeColor);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildResultView(StudyViewModel viewModel, bool isDarkMode, Color themeColor) {
    final bool isPerfect = viewModel.score == viewModel.total;
    final Color textColor = isDarkMode ? Colors.white : Colors.black87;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isPerfect 
                        ? [Colors.orange.withOpacity(0.2), Colors.orange.withOpacity(0.05)] 
                        : [themeColor.withOpacity(0.2), themeColor.withOpacity(0.05)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(isPerfect ? Icons.workspace_premium_rounded : Icons.auto_awesome_rounded, 
                       size: 60, color: isPerfect ? Colors.orange : themeColor),
                ),
                const SizedBox(height: 20),
                Text(isPerfect ? '완벽합니다! 💯' : '조금 더 힘내볼까요? 💪', 
                     textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: textColor)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: isDarkMode ? [] : [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${viewModel.score}', style: TextStyle(color: themeColor, fontSize: 32, fontWeight: FontWeight.w900)),
                      Text(' / ${viewModel.total}', style: TextStyle(color: isDarkMode ? Colors.white24 : Colors.grey[400], fontSize: 22, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(height: 36),
                
                if (!isPerfect) ...[
                  Row(children: [
                    Container(width: 4, height: 18, decoration: BoxDecoration(color: themeColor, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 10), 
                    Text('틀린 단어 꼼꼼하게 복습', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: textColor))
                  ]),
                  const SizedBox(height: 16),
                  ...List.generate(viewModel.sessionWords.length, (index) {
                    final word = viewModel.sessionWords[index];
                    final userAnswer = viewModel.userAnswers[index];
                    if (userAnswer == word.meaning || userAnswer == word.kanji || userAnswer == word.kana) return const SizedBox.shrink();
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: isDarkMode ? const Color(0xFF252525) : Colors.white, 
                        borderRadius: BorderRadius.circular(20), 
                        border: Border.all(color: Colors.redAccent.withOpacity(isDarkMode ? 0.1 : 0.05)),
                        boxShadow: isDarkMode ? [] : [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8)],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.1), shape: BoxShape.circle),
                            child: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 18),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start, 
                              children: [
                                Text('${word.kanji} (${word.kana})', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor)), 
                                const SizedBox(height: 8), 
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 4,
                                  children: [
                                    RichText(text: TextSpan(children: [
                                      TextSpan(text: '내 답: ', style: TextStyle(fontSize: 13, color: isDarkMode ? Colors.white24 : Colors.grey[500])),
                                      TextSpan(text: userAnswer ?? '없음', style: const TextStyle(fontSize: 13, color: Colors.redAccent, fontWeight: FontWeight.w600)),
                                    ])),
                                    RichText(text: TextSpan(children: [
                                      TextSpan(text: '정답: ', style: TextStyle(fontSize: 13, color: isDarkMode ? Colors.white24 : Colors.grey[500])),
                                      TextSpan(text: word.meaning, style: TextStyle(fontSize: 13, color: themeColor, fontWeight: FontWeight.bold)),
                                    ])),
                                  ],
                                ),
                              ]
                            )
                          )
                        ]
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          decoration: BoxDecoration(
            color: isDarkMode ? Colors.transparent : Colors.white.withOpacity(0.5),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: () => viewModel.restart(),
                  icon: const Icon(Icons.replay_rounded, size: 20),
                  label: const Text('다시 도전하기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeColor,
                    foregroundColor: isDarkMode ? Colors.black87 : Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                  icon: const Icon(Icons.home_rounded, size: 20),
                  label: const Text('학습 마치기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: themeColor.withOpacity(0.5), width: 2),
                    foregroundColor: themeColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuizView(BuildContext context, StudyViewModel viewModel, bool isDarkMode, Color textColor, Color themeColor) {
    final bool isLast = viewModel.currentIndex == (viewModel.total - 1);
    final word = viewModel.currentWord!;
    final type = viewModel.currentQuizType!;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 5),
          child: Column(
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('${(viewModel.currentIndex + 1).clamp(1, viewModel.total > 0 ? viewModel.total : 1)} / ${viewModel.total}', 
                     style: TextStyle(color: isDarkMode ? Colors.white38 : Colors.grey[600], fontSize: 13, fontWeight: FontWeight.bold)), 
                Text('정답: ${viewModel.score}', style: const TextStyle(color: Colors.green, fontSize: 13, fontWeight: FontWeight.bold))
              ]),
              const SizedBox(height: 6),
              ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(
                value: viewModel.total > 0 ? (viewModel.currentIndex + 1) / viewModel.total : 0, 
                minHeight: 5, 
                backgroundColor: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.grey[200], 
                valueColor: AlwaysStoppedAnimation<Color>(themeColor)
              )),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                Container(
                  constraints: const BoxConstraints(minHeight: 180), // 배지 제거로 공간 여유 확보를 위해 높이 소폭 하향
                  alignment: Alignment.center, 
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
                  decoration: BoxDecoration(
                    color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white, 
                    borderRadius: BorderRadius.circular(24),
                    border: isDarkMode ? Border.all(color: Colors.white.withOpacity(0.03)) : null,
                    boxShadow: isDarkMode ? [] : [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // [삭제] 이미 레벨을 선택하고 왔으므로 상단 레벨 배지 제거 (공간 확보)
                      if (type == QuizType.kanjiToMeaning) ...[
                        Visibility(
                          maintainSize: true,
                          maintainAnimation: true,
                          maintainState: true,
                          visible: viewModel.isAnswered,
                          child: Text(word.kana, style: TextStyle(fontSize: 16, color: isDarkMode ? Colors.white38 : Colors.grey[500])),
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(word.kanji, style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: textColor)),
                        ),
                        const SizedBox(height: 8),
                        Opacity(
                          opacity: viewModel.isAnswered ? 1.0 : 0.0,
                          child: Text('[ ${word.koreanPronunciation} ]', style: TextStyle(fontSize: 16, color: themeColor, fontWeight: FontWeight.w600)),
                        ),
                      ] else ...[
                        Text('다음 뜻에 맞는 단어는?', style: TextStyle(fontSize: 14, color: isDarkMode ? Colors.white38 : Colors.blueGrey)),
                        const SizedBox(height: 12),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(word.meaning, textAlign: TextAlign.center, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: textColor)),
                        ),
                        const SizedBox(height: 8),
                        Visibility(
                          maintainSize: true,
                          maintainAnimation: true,
                          maintainState: true,
                          visible: viewModel.isAnswered,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('${word.kanji} (${word.kana}) [${word.koreanPronunciation}]', style: TextStyle(fontSize: 16, color: themeColor, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                ...viewModel.currentOptionWords.map((optionWord) => 
                  _buildOptionButton(
                    viewModel, 
                    optionWord, 
                    isDarkMode, 
                    themeColor, 
                    key: ValueKey('opt_${viewModel.currentIndex}_${optionWord.id}')
                  )
                ),
              ],
            ),
          ),
        ),
        if (viewModel.isAnswered) 
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 30), 
            child: SizedBox(
              width: double.infinity, 
              height: 56, 
              child: ElevatedButton(
                onPressed: () => viewModel.nextQuestion(), 
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDarkMode ? themeColor.withOpacity(0.2) : const Color(0xFF2D3142), 
                  foregroundColor: Colors.white, 
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ), 
                child: Text(isLast ? '결과 보기' : '다음 문제', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))
              )
            )
          ),
      ],
    );
  }

  Widget _buildOptionButton(StudyViewModel viewModel, Word optionWord, bool isDarkMode, Color themeColor, {Key? key}) {
    final type = viewModel.currentQuizType!;
    String buttonDisplayLabel = "";
    bool isCorrectChoice = false;
    
    switch (type) {
      case QuizType.kanjiToMeaning: 
        buttonDisplayLabel = optionWord.meaning; 
        isCorrectChoice = optionWord.meaning == viewModel.currentWord!.meaning; 
        break;
      case QuizType.meaningToKanji: 
        buttonDisplayLabel = optionWord.kanji; 
        isCorrectChoice = optionWord.kanji == viewModel.currentWord!.kanji; 
        break;
      case QuizType.meaningToKana: 
        buttonDisplayLabel = optionWord.kana; 
        isCorrectChoice = optionWord.kana == viewModel.currentWord!.kana; 
        break;
    }
    
    bool isSelected = buttonDisplayLabel == viewModel.selectedAnswer;
    bool isAnswered = viewModel.isAnswered;
    
    Color backgroundColor = isDarkMode ? const Color(0xFF252525) : Colors.white;
    Color borderColor = isDarkMode ? Colors.white.withOpacity(0.05) : Colors.grey[200]!;
    Color textColor = isDarkMode ? const Color(0xFFBDBDBD) : Colors.black87;
    
    if (isAnswered) {
      if (isCorrectChoice) { 
        backgroundColor = Colors.green.withOpacity(isDarkMode ? 0.15 : 0.08); 
        borderColor = Colors.green.withOpacity(0.6); 
        textColor = isDarkMode ? Colors.greenAccent : Colors.green[700]!; 
      } else if (isSelected) { 
        backgroundColor = Colors.red.withOpacity(isDarkMode ? 0.15 : 0.08); 
        borderColor = Colors.red.withOpacity(0.6); 
        textColor = isDarkMode ? Colors.redAccent : Colors.red[700]!; 
      } else {
        textColor = isDarkMode ? Colors.white10 : Colors.grey[300]!;
      }
    }

    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () {
          if (!isAnswered) {
            viewModel.submitAnswer(buttonDisplayLabel);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 85,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor, width: 2),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(buttonDisplayLabel, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: textColor), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Visibility(
                      maintainSize: true,
                      maintainAnimation: true,
                      maintainState: true,
                      visible: isAnswered,
                      child: Column(
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            type == QuizType.kanjiToMeaning ? '${optionWord.kanji} (${optionWord.kana})' : optionWord.koreanPronunciation,
                            style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.5)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (isAnswered && isCorrectChoice) const Icon(Icons.check_circle_rounded, color: Colors.green, size: 24),
              if (isSelected && !isCorrectChoice) const Icon(Icons.cancel_rounded, color: Colors.red, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}
