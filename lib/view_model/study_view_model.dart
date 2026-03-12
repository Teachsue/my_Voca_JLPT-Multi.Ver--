import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../model/word.dart';
import '../service/database_service.dart';
import '../service/supabase_service.dart';

enum QuizType { kanjiToMeaning, meaningToKanji, meaningToKana }

class StudyViewModel extends ChangeNotifier {
  final Box<Word> _wordBox = Hive.box<Word>(DatabaseService.boxName);
  final Box _sessionBox = Hive.box(DatabaseService.sessionBoxName);

  List<Word> sessionWords = [];
  int currentIndex = 0;
  int score = 0;
  bool isFinished = false;
  bool isAnswered = false;
  String? selectedAnswer;
  QuizType? currentQuizType;
  List<Word> currentOptionWords = [];
  Map<int, String> userAnswers = {};

  int? _currentLevel;
  int? _currentDay;
  bool _isProcessingFinish = false;

  static const List<int> _srsIntervals = [0, 4, 8, 24, 48, 168, 336, 720];

  Word? get currentWord => sessionWords.isNotEmpty && currentIndex < sessionWords.length ? sessionWords[currentIndex] : null;
  int get total => sessionWords.length;

  int getChunkSize(int level) => 20;

  void _safeNotify() {
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      notifyListeners();
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    }
  }

  /// 특정 레벨의 단어 로드 (순서 및 개수 고정)
  Future<void> loadWords(int level, {int questionCount = 10, int? day, List<Word>? initialWords}) async {
    _currentLevel = level;
    _currentDay = day;
    _isProcessingFinish = false;

    if (initialWords != null && initialWords.isNotEmpty) {
      // [개선] 전달받은 단어 리스트를 퀴즈 시에는 랜덤하게 섞음 (학습 효과 극대화)
      sessionWords = List.from(initialWords)..shuffle();
    } else {
      final List<Word> words = _wordBox.values.where((w) => w.level == level).toList();
      words.sort((a, b) => a.id.compareTo(b.id));
      words.shuffle(Random(42)); // 기본 레벨 학습은 고정된 셔플 사용

      if (day != null && day > 0) {
        int chunkSize = getChunkSize(level);
        int start = (day - 1) * chunkSize;
        sessionWords = words.skip(start).take(chunkSize).toList();
      } else {
        sessionWords = words.take(questionCount).toList();
      }
      
      // 문제 출제 순서를 최종적으로 한 번 더 섞음
      sessionWords.shuffle();
    }
    _resetQuizState();
    _safeNotify();
  }

  /// 오늘의 단어 (10개) - 자정까지 완벽 고정 로직
  Future<List<Word>> loadTodaysWords() async {
    final String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final String? savedDate = _sessionBox.get('todays_words_fixed_date');
    final List<dynamic>? savedIds = _sessionBox.get('todays_words_fixed_ids');

    if (savedDate == today && savedIds != null && savedIds.isNotEmpty) {
      List<Word> cachedWords = [];
      for (var id in savedIds) {
        try {
          final word = _wordBox.values.firstWhere((w) => w.id == id);
          cachedWords.add(word);
        } catch (_) {}
      }
      if (cachedWords.length == 10) return cachedWords;
    }

    List<Word> allLevelWords = _wordBox.values.where((w) => w.level >= 1 && w.level <= 5).toList();
    allLevelWords.shuffle();
    List<Word> selected = allLevelWords.take(10).toList();
    
    await _sessionBox.put('todays_words_fixed_date', today);
    await _sessionBox.put('todays_words_fixed_ids', selected.map((w) => w.id).toList());
    
    return selected;
  }

  void _resetQuizState() {
    currentIndex = 0;
    score = 0;
    isFinished = false;
    isAnswered = false;
    selectedAnswer = null;
    userAnswers.clear();
    _prepareQuestion();
  }

  void _prepareQuestion() {
    if (currentIndex >= sessionWords.length) {
      isFinished = true;
      if (!_isProcessingFinish) {
        _isProcessingFinish = true;
        _onQuizFinished();
      }
      return;
    }
    isAnswered = false;
    selectedAnswer = null;
    final word = sessionWords[currentIndex];
    
    final types = [QuizType.kanjiToMeaning, QuizType.meaningToKanji];
    if (word.level == 11 || word.level == 12) types.add(QuizType.meaningToKana);
    currentQuizType = (types..shuffle()).first;

    List<Word> others = _wordBox.values.where((w) => w.id != word.id && w.level == word.level).toList();
    if (others.length < 3) {
      others = _wordBox.values.where((w) => w.id != word.id).toList();
    }
    others.shuffle();
    currentOptionWords = [word, ...others.take(3)]..shuffle();
  }

  Future<void> _onQuizFinished() async {
    if (_currentLevel != null) {
      await clearSession(_currentLevel!, _currentDay);
    }
    await syncProgressToServer();
    _safeNotify();
  }

  Future<void> submitAnswer(String answer) async {
    if (isAnswered) return;
    isAnswered = true;
    selectedAnswer = answer;
    userAnswers[currentIndex] = answer;

    final word = currentWord!;
    bool isCorrect = false;
    if (currentQuizType == QuizType.kanjiToMeaning) isCorrect = (answer == word.meaning);
    else if (currentQuizType == QuizType.meaningToKanji) isCorrect = (answer == word.kanji);
    else isCorrect = (answer == word.kana);

    if (isCorrect) {
      score++;
      HapticFeedback.lightImpact(); // [추가] 정답 시 가벼운 진동
      await _updateWordSRS(word, true);
    } else {
      HapticFeedback.mediumImpact(); // [추가] 오답 시 중간 진동
      await _updateWordSRS(word, false);
    }
    
    if (_currentLevel != null) {
      saveSession(_currentLevel!, _currentDay);
    }
    _safeNotify();
  }

  Future<void> _updateWordSRS(Word word, bool isCorrect) async {
    if (isCorrect) {
      word.correct_count++;
      word.srs_stage = (word.srs_stage + 1).clamp(0, 7);
      if (word.srs_stage >= 7) {
        word.status = 'mastered';
        word.is_memorized = true;
      } else {
        word.status = 'studying';
      }
    } else {
      word.incorrect_count++;
      word.srs_stage = (word.srs_stage - 2).clamp(0, 7);
      word.status = 'studying';
      word.is_wrong_note = true;
    }

    if (word.srs_stage > 0) {
      word.next_review_at = DateTime.now().add(Duration(hours: _srsIntervals[word.srs_stage]));
    } else {
      word.next_review_at = null;
    }
    await word.save();
  }

  Map<dynamic, dynamic>? getSavedSession(int level, int? day) {
    final String key = 'quiz_session_${level}_$day';
    return _sessionBox.get(key);
  }

  Future<void> saveSession(int level, int? day) async {
    final String key = 'quiz_session_${level}_$day';
    await _sessionBox.put(key, {
      'currentIndex': currentIndex,
      'score': score,
      'userAnswers': userAnswers,
      'sessionWordsIds': sessionWords.map((w) => w.id).toList(),
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  Future<void> resumeSession(int level, int? day) async {
    _currentLevel = level;
    _currentDay = day;
    _isProcessingFinish = false;
    final String key = 'quiz_session_${level}_$day';
    final Map<dynamic, dynamic>? session = _sessionBox.get(key);
    if (session != null) {
      currentIndex = session['currentIndex'] ?? 0;
      score = session['score'] ?? 0;
      userAnswers = Map<int, String>.from(session['userAnswers'] ?? {});
      final List<dynamic> ids = session['sessionWordsIds'] ?? [];
      
      sessionWords = [];
      for (var id in ids) {
        try {
          final word = _wordBox.values.firstWhere((w) => w.id == id);
          sessionWords.add(word);
        } catch (_) {}
      }
      
      isFinished = currentIndex >= sessionWords.length;
      if (!isFinished) _prepareQuestion();
      _safeNotify();
    }
  }

  Future<void> clearSession(int level, int? day) async {
    await _sessionBox.delete('quiz_session_${level}_$day');
  }

  void restart() {
    _resetQuizState();
    // 재시작 시에도 섞어줌
    sessionWords.shuffle();
    _safeNotify();
  }

  Future<void> syncProgressToServer() async {
    if (SupabaseService.isGoogleLinked) {
      await SupabaseService.uploadLocalDataToCloud();
      
      // 오늘의 단어 모드(day == 0)에서 만점 여부 확인
      bool isTodaysPerfect = (_currentDay == 0 && score == total && total > 0);

      await SupabaseService.updateStudyLog(
        learnedCount: sessionWords.where((w) => w.correct_count == 1).length,
        reviewCount: sessionWords.where((w) => w.correct_count > 1).length,
        testScore: total > 0 ? (score / total) * 100 : 0,
        isTodaysPerfect: isTodaysPerfect, // [추가] 만점 여부 서버 전송
      );
    }
  }

  void nextQuestion() {
    if (currentIndex < sessionWords.length) {
      isAnswered = false; 
      selectedAnswer = null;
      currentIndex++;
      _prepareQuestion();
      _safeNotify();
    }
  }

  Future<List<List<Word>>> loadLevelWords(String level) async {
    int levelInt = 5;
    if (level == 'N5') levelInt = 5;
    else if (level == 'N4') levelInt = 4;
    else if (level == 'N3') levelInt = 3;
    else if (level == 'N2') levelInt = 2;
    else if (level == 'N1') levelInt = 1;
    else if (level == '히라가나') levelInt = 11;
    else if (level == '가타카나') levelInt = 12;

    final List<Word> words = _wordBox.values.where((w) => w.level == levelInt).toList();
    words.sort((a, b) => a.id.compareTo(b.id));
    words.shuffle(Random(42));

    int chunkSize = getChunkSize(levelInt);
    List<List<Word>> chunks = [];
    for (var i = 0; i < words.length; i += chunkSize) {
      int end = (i + chunkSize > words.length) ? words.length : i + chunkSize;
      List<Word> chunk = words.sublist(i, end);
      if (chunks.isNotEmpty && chunk.length < 10) {
        chunks.last.addAll(chunk);
      } else {
        chunks.add(chunk);
      }
    }
    return chunks;
  }
}
