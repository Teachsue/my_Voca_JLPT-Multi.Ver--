import 'dart:math';
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

  int getChunkSize(int level) {
    // 모든 레벨(N5~N1, 기초 등)에서 Day당 20개씩 학습하도록 설정
    return 20;
  }

  Future<void> loadWords(int level, {int questionCount = 10, int? day, List<Word>? initialWords}) async {
    if (initialWords != null) {
      sessionWords = List.from(initialWords)..shuffle();
    } else {
      // 1. 해당 레벨의 모든 단어 불러오기
      final List<Word> words = _wordBox.values.where((w) => w.level == level).toList();
      
      // 2. ID 기준으로 정렬 후 고정 시드(42)로 셔플하여 항상 동일한 학습 순서 보장
      // (비슷한 발음이 모이는 것을 방지하기 위해 섞음)
      words.sort((a, b) => a.id.compareTo(b.id));
      words.shuffle(Random(42));

      if (day != null && day > 0) {
        // 3. 레벨별 적절한 Day당 단어 개수(20개) 가져오기
        int chunkSize = getChunkSize(level);
        int start = (day - 1) * chunkSize;
        sessionWords = words.skip(start).take(chunkSize).toList();
      } else {
        // 랜덤 학습 모드
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
  }

  /// [신규] 퀴즈 종료 시 로컬의 모든 변경사항을 서버에 한 번만 전송합니다.
  Future<void> syncProgressToServer() async {
    if (SupabaseService.isGoogleLinked) {
      await SupabaseService.uploadLocalDataToCloud();
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

  /// [신규] 특정 레벨의 모든 단어를 가져와서 레벨별 정해진 개수(20개)씩 묶어 반환합니다.
  Future<List<List<Word>>> loadLevelWords(String level) async {
    int levelInt = 5;
    if (level == 'N5') levelInt = 5;
    else if (level == 'N4') levelInt = 4;
    else if (level == 'N3') levelInt = 3;
    else if (level == 'N2') levelInt = 2;
    else if (level == 'N1') levelInt = 1;
    else if (level == '히라가나') levelInt = 11;
    else if (level == '가타카나') levelInt = 12;

    // 1. 해당 레벨의 모든 단어 불러오기
    final List<Word> words = _wordBox.values.where((w) => w.level == levelInt).toList();
    
    // 2. ID 기준으로 정렬 후 고정 시드(42)로 셔플하여 항상 동일한 순서 유지
    // (이어하기와 단어장 메뉴의 순서를 일치시키기 위함)
    words.sort((a, b) => a.id.compareTo(b.id));
    words.shuffle(Random(42));

    // 3. 모든 레벨 Day당 20개 적용
    int chunkSize = getChunkSize(levelInt);

    // 4. 단어 묶기(Chunking)
    List<List<Word>> chunks = [];
    for (var i = 0; i < words.length; i += chunkSize) {
      int end = (i + chunkSize > words.length) ? words.length : i + chunkSize;
      List<Word> chunk = words.sublist(i, end);
      
      // 마지막 묶음이 10개 미만이면 이전 묶음에 합침 (단, 이전 묶음이 존재할 때만)
      if (chunks.isNotEmpty && chunk.length < 10) {
        chunks.last.addAll(chunk);
      } else {
        chunks.add(chunk);
      }
    }
    return chunks;
  }
}
