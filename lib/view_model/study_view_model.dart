import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../model/word.dart';
import '../service/database_service.dart';
import '../service/supabase_service.dart';

enum QuizType { kanjiToMeaning, meaningToKanji, meaningToKana }

class StudyViewModel extends ChangeNotifier {
  final Box<Word> _wordBox = Hive.box<Word>(DatabaseService.boxName);

  List<Word> sessionWords = [];
  int currentIndex = 0;
  int score = 0;
  bool isFinished = false;
  bool isAnswered = false;
  String? selectedAnswer;
  QuizType? currentQuizType;
  List<Word> currentOptionWords = [];
  Map<int, String> userAnswers = {};

  static const List<int> _srsIntervals = [0, 4, 8, 24, 48, 168, 336, 720];

  Word? get currentWord => sessionWords.isNotEmpty ? sessionWords[currentIndex] : null;
  int get total => sessionWords.length;

  Future<void> loadWords(int level, {int questionCount = 10, int? day, List<Word>? initialWords}) async {
    if (initialWords != null) {
      sessionWords = List.from(initialWords)..shuffle();
    } else {
      final List<Word> words = _wordBox.values.where((w) => w.level == level).toList();
      if (day != null && day > 0) {
        int start = (day - 1) * questionCount;
        sessionWords = words.skip(start).take(questionCount).toList();
      } else {
        sessionWords = words..shuffle();
        sessionWords = sessionWords.take(questionCount).toList();
      }
    }
    _resetQuizState();
    notifyListeners();
  }

  Future<List<Word>> loadTodaysWords() async {
    final sessionBox = Hive.box(DatabaseService.sessionBoxName);
    final String? recommendedLevel = sessionBox.get('recommended_level');
    int levelInt = 5;
    if (recommendedLevel != null) {
      if (recommendedLevel.contains('N')) levelInt = int.tryParse(recommendedLevel.replaceAll('N', '')) ?? 5;
      else if (recommendedLevel.contains('히라가나')) levelInt = 11;
      else if (recommendedLevel.contains('가타카나')) levelInt = 12;
    }

    List<Word> unlearned = _wordBox.values.where((w) => w.level == levelInt && w.status == 'unlearned').toList();
    if (unlearned.length < 10) {
      unlearned.addAll(_wordBox.values.where((w) => w.level == levelInt && w.status == 'studying').take(10 - unlearned.length));
    }
    unlearned.shuffle();
    return unlearned.take(10).toList();
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
      return;
    }
    isAnswered = false;
    selectedAnswer = null;
    final word = sessionWords[currentIndex];
    
    final types = [QuizType.kanjiToMeaning, QuizType.meaningToKanji];
    if (word.level == 11 || word.level == 12) types.add(QuizType.meaningToKana);
    currentQuizType = (types..shuffle()).first;

    List<Word> others = _wordBox.values.where((w) => w.id != word.id && w.level == word.level).toList();
    others.shuffle();
    currentOptionWords = [word, ...others.take(3)]..shuffle();
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
      await _updateWordSRS(word, true);
    } else {
      await _updateWordSRS(word, false);
    }
    notifyListeners();
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
    // [최적화] 여기서 실시간 서버 통신(upsertWordProgress, updateStudyLog)을 제거했습니다.
  }

  /// [신규] 퀴즈 종료 시 로컬의 모든 변경사항을 서버에 한 번만 전송합니다.
  Future<void> syncProgressToServer() async {
    if (SupabaseService.isGoogleLinked) {
      await SupabaseService.uploadLocalDataToCloud();
      // 오늘 공부한 통계 기록 (단순화하여 전체 맞춘 개수를 점수로 전송)
      await SupabaseService.updateStudyLog(
        learnedCount: sessionWords.where((w) => w.correct_count == 1).length,
        reviewCount: sessionWords.where((w) => w.correct_count > 1).length,
        testScore: (score / total) * 100,
      );
    }
  }

  void nextQuestion() {
    currentIndex++;
    _prepareQuestion();
    notifyListeners();
  }

  void restart() {
    _resetQuizState();
    notifyListeners();
  }

  Map<String, dynamic>? getSavedSession(int level, int? day) {
    final box = Hive.box(DatabaseService.sessionBoxName);
    return box.get('quiz_session_${level}_$day');
  }

  void resumeSession(Map<String, dynamic> session) {
    currentIndex = session['currentIndex'];
    score = session['score'];
    userAnswers = Map<int, String>.from(session['userAnswers']);
    _prepareQuestion();
    notifyListeners();
  }
}
