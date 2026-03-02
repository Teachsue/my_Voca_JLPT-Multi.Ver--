import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:math';
import '../model/word.dart';
import '../service/database_service.dart';
import '../service/supabase_service.dart';

enum QuizType { kanjiToMeaning, meaningToKanji, meaningToKana }

class StudyViewModel extends ChangeNotifier {
  List<Word> _words = [];
  List<QuizType> _quizTypes = []; // 각 문제의 유형 저장
  int _currentIndex = 0;
  int _score = 0;
  bool _isAnswered = false;
  bool _isCorrect = false;
  String? _selectedAnswer;
  List<Word> _currentOptionWords = [];
  List<String?> _userAnswers = [];
  String? _currentSessionKey;

  // Getters
  Word? get currentWord => (_words.isNotEmpty && _currentIndex < _words.length) ? _words[_currentIndex] : null;
  QuizType? get currentQuizType => (_quizTypes.isNotEmpty && _currentIndex < _quizTypes.length) ? _quizTypes[_currentIndex] : null;
  List<Word> get currentOptionWords => _currentOptionWords;
  List<String?> get userAnswers => _userAnswers;
  List<Word> get sessionWords => _words;
  bool get isAnswered => _isAnswered;
  bool get isCorrect => _isCorrect;
  String? get selectedAnswer => _selectedAnswer;
  int get score => _score;
  int get total => _words.length;
  int get currentIndex => _currentIndex;
  bool get isFinished => _words.isNotEmpty && _currentIndex >= _words.length;

  String _generateSessionKey(int level, int? day) {
    return day == null ? 'quiz_level_$level' : 'quiz_level_${level}_day_$day';
  }

  Map<String, dynamic>? getSavedSession(int level, int? day) {
    final box = Hive.box(DatabaseService.sessionBoxName);
    final key = _generateSessionKey(level, day);
    final data = box.get(key);
    if (data != null && data['currentIndex'] > 0) return Map<String, dynamic>.from(data);
    return null;
  }

  Future<void> loadWords(int level, {int? questionCount, int? day, List<Word>? initialWords}) async {
    _currentSessionKey = _generateSessionKey(level, day);
    
    // 새로 시작하므로 기존에 저장된 해당 세션 기록을 삭제
    _clearSession();
    
    if (initialWords != null) {
      var shuffled = List<Word>.from(initialWords)..shuffle();
      int count = (questionCount != null && questionCount < shuffled.length) ? questionCount : shuffled.length;
      _words = shuffled.take(count).toList();
    } else {
      final allWords = DatabaseService.getWordsByLevel(level);
      allWords.shuffle();
      int count = questionCount ?? 10;
      _words = allWords.take(count).toList();
    }
    
    // 문제 유형 랜덤 배정
    _quizTypes = List.generate(_words.length, (_) => QuizType.values[Random().nextInt(QuizType.values.length)]);
    
    _currentIndex = 0;
    _score = 0;
    _isAnswered = false;
    _userAnswers = List.filled(_words.length, null);
    if (_words.isNotEmpty) _generateOptions();
    notifyListeners();
  }

  // 오늘의 단어 로드 (에빙하우스 망각곡선 적용)
  Future<List<Word>> loadTodaysWords() async {
    final box = Hive.box(DatabaseService.sessionBoxName);
    final today = DateTime.now().toString().split(' ')[0];
    final sessionKey = 'todays_words_$today';
    
    // 이미 오늘 생성된 세션이 있다면 해당 단어들 반환
    final savedIds = box.get(sessionKey);
    final wordsBox = Hive.box<Word>(DatabaseService.boxName);
    List<Word> todaysWords = [];

    if (savedIds != null) {
      final List<dynamic> ids = List.from(savedIds);
      final allWords = wordsBox.values.toList();
      for (var id in ids) {
        try {
          todaysWords.add(allWords.firstWhere((w) => w.id == id));
        } catch (e) {}
      }
      if (todaysWords.isNotEmpty) return todaysWords;
    }

    // 1. 복습이 필요한 단어들 추출 (nextReviewDate가 오늘이거나 과거인 단어)
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    
    List<Word> reviewDueWords = wordsBox.values.where((w) {
      if (w.nextReviewDate == null) return false;
      // 시간 제외하고 날짜만 비교
      final nextDate = DateTime(w.nextReviewDate!.year, w.nextReviewDate!.month, w.nextReviewDate!.day);
      return nextDate.isBefore(todayDate) || nextDate.isAtSameMomentAs(todayDate);
    }).toList();

    // 2. 복습 단어를 최대 10개까지 선택
    reviewDueWords.shuffle();
    todaysWords = reviewDueWords.take(10).toList();

    // 3. 10개가 안 채워졌다면 신규 단어(srsStage == 0)로 채움
    if (todaysWords.length < 10) {
      final newWords = wordsBox.values.where((w) => (w.srsStage == 0 || w.srsStage == null) && !todaysWords.contains(w)).toList();
      newWords.shuffle();
      final neededCount = 10 - todaysWords.length;
      todaysWords.addAll(newWords.take(neededCount));
    }

    // 4. 세션 저장 (오늘 하루 동안은 동일한 단어 구성 유지)
    box.put(sessionKey, todaysWords.map((w) => w.id).toList());

    return todaysWords;
  }

  void resumeSession(Map<String, dynamic> sessionData) {
    final wordIds = List<int>.from(sessionData['wordIds']);
    final box = Hive.box<Word>(DatabaseService.boxName);
    
    _words = [];
    final allWords = box.values.toList();
    for (var id in wordIds) {
      try {
        _words.add(allWords.firstWhere((w) => w.id == id));
      } catch (e) {}
    }

    // 유형 복구 (없으면 랜덤 생성)
    if (sessionData['quizTypes'] != null) {
      _quizTypes = (sessionData['quizTypes'] as List).map((e) => QuizType.values[e]).toList();
    } else {
      _quizTypes = List.generate(_words.length, (_) => QuizType.values[Random().nextInt(QuizType.values.length)]);
    }

    _currentIndex = sessionData['currentIndex'];
    _score = sessionData['score'];
    _currentSessionKey = sessionData['sessionKey'];
    
    if (sessionData['userAnswers'] != null) {
      _userAnswers = List<String?>.from(sessionData['userAnswers']);
    } else {
      _userAnswers = List.filled(_words.length, null);
    }

    _isAnswered = false;
    _selectedAnswer = null;
    
    if (_words.isNotEmpty && !isFinished) _generateOptions();
    notifyListeners();
  }

  void _generateOptions() {
    if (currentWord == null || currentQuizType == null) return;
    final correctWord = currentWord!;
    final type = currentQuizType!;
    
    List<Word> allWords;
    if (correctWord.level == 0 || correctWord.level < 1) {
      allWords = Hive.box<Word>(DatabaseService.boxName).values.toList();
    } else {
      allWords = DatabaseService.getWordsByLevel(correctWord.level);
    }

    // 유형별로 중복되지 않는 보기 추출 로직
    final distractors = allWords.where((w) {
      if (w.id == correctWord.id) return false;
      switch (type) {
        case QuizType.kanjiToMeaning: 
          return w.meaning != correctWord.meaning;
        case QuizType.meaningToKanji: 
          return w.kanji != correctWord.kanji;
        case QuizType.meaningToKana: 
          return w.kana != correctWord.kana;
      }
    }).toList();
    
    distractors.shuffle();
    _currentOptionWords = [correctWord, ...distractors.take(3)];
    _currentOptionWords.shuffle();
  }

  void submitAnswer(String answer) {
    if (_isAnswered || currentWord == null) return;
    _isAnswered = true;
    _selectedAnswer = answer;
    _userAnswers[_currentIndex] = answer;

    // 유형에 따른 정답 체크
    bool correct = false;
    switch (currentQuizType!) {
      case QuizType.kanjiToMeaning: correct = answer == currentWord!.meaning; break;
      case QuizType.meaningToKanji: correct = answer == currentWord!.kanji; break;
      case QuizType.meaningToKana: correct = answer == currentWord!.kana; break;
    }

    if (correct) {
      _isCorrect = true;
      _score++;
      currentWord!.correctCount++;
      
      // SRS 단계 상승 로직 (복습 주기 업데이트)
      _advanceSRSStage(currentWord!);
    } else {
      _isCorrect = false;
      currentWord!.incorrectCount++;
      
      // SRS 단계 초기화 (틀리면 처음부터 다시)
      _resetSRSStage(currentWord!);
    }
    currentWord!.save();
    
    // Supabase에 데이터 동기화
    SupabaseService.upsertWordProgress(currentWord!);

    _updateDailyStudyCount();
    _saveCurrentSession();
    notifyListeners();
  }

  void _advanceSRSStage(Word word) {
    word.srsStage = (word.srsStage ?? 0) + 1;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    // 단계별 복습 주기 (일 단위)
    int interval = 0;
    switch (word.srsStage) {
      case 1: interval = 1; break;  // 1단계: 1일 후 복습
      case 2: interval = 2; break;  // 2단계: 2일 후
      case 3: interval = 4; break;  // 3단계: 4일 후
      case 4: interval = 7; break;  // 4단계: 7일 후
      case 5: interval = 14; break; // 5단계: 14일 후
      case 6: interval = 30; break; // 6단계: 30일 후 (마스터 단계)
      default: interval = 30;
    }
    
    word.nextReviewDate = today.add(Duration(days: interval));
  }

  void _resetSRSStage(Word word) {
    word.srsStage = 0;
    word.nextReviewDate = null; // 신규 단어로 다시 분류
  }

  void _updateDailyStudyCount() {
    final box = Hive.box(DatabaseService.sessionBoxName);
    final today = DateTime.now().toString().split(' ')[0];
    final currentCount = box.get('study_count_$today', defaultValue: 0);
    box.put('study_count_$today', currentCount + 1);
  }

  void _saveCurrentSession() {
    if (_currentSessionKey == null || _words.isEmpty) return;
    final box = Hive.box(DatabaseService.sessionBoxName);
    box.put(_currentSessionKey, {
      'sessionKey': _currentSessionKey,
      'wordIds': _words.map((w) => w.id).toList(),
      'quizTypes': _quizTypes.map((e) => e.index).toList(), // 유형 인덱스 저장
      'currentIndex': _currentIndex,
      'score': _score,
      'userAnswers': _userAnswers,
    });
  }

  void nextQuestion() {
    _currentIndex++;
    _isAnswered = false;
    _selectedAnswer = null;
    if (!isFinished) {
      _generateOptions();
      _saveCurrentSession();
    } else {
      _clearSession();
    }
    notifyListeners();
  }

  void _clearSession() {
    if (_currentSessionKey != null) Hive.box(DatabaseService.sessionBoxName).delete(_currentSessionKey);
  }

  void markTodaysWordsAsCompleted() {
    final box = Hive.box(DatabaseService.sessionBoxName);
    final today = DateTime.now().toString().split(' ')[0];
    box.put('todays_words_completed_$today', true);
  }

  void restart() {
    _clearSession();
    _words.shuffle();
    // 다시 시작할 때 유형도 랜덤 재배정
    _quizTypes = List.generate(_words.length, (_) => QuizType.values[Random().nextInt(QuizType.values.length)]);
    _currentIndex = 0;
    _score = 0;
    _isAnswered = false;
    _generateOptions();
    notifyListeners();
  }
}
