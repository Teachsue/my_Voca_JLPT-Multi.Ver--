import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:math';
import '../model/word.dart';
import '../service/database_service.dart';

enum LevelTestType { kanjiToMeaning, meaningToKanji, meaningToKana }

class LevelTestViewModel extends ChangeNotifier {
  List<Word> _questions = [];
  List<LevelTestType> _testTypes = [];
  int _currentIndex = 0;
  bool _isFinished = false;

  final Map<int, int> _correctCountsPerLevel = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
  int _totalCorrect = 0;

  bool _isAnswered = false;
  String? _selectedAnswer;
  List<String> _currentOptions = [];

  // Getters
  Word? get currentWord => (_questions.isNotEmpty && _currentIndex < _questions.length) ? _questions[_currentIndex] : null;
  LevelTestType? get currentType => (_testTypes.isNotEmpty && _currentIndex < _testTypes.length) ? _testTypes[_currentIndex] : null;
  int get currentIndex => _currentIndex;
  int get totalQuestions => _questions.length;
  bool get isFinished => _isFinished;
  bool get isAnswered => _isAnswered;
  String? get selectedAnswer => _selectedAnswer;
  List<String> get currentOptions => _currentOptions;

  Future<void> initTest() async {
    _questions = [];
    _currentIndex = 0;
    _isFinished = false;
    _totalCorrect = 0;
    _correctCountsPerLevel.updateAll((key, value) => 0);

    _questions.addAll(_getRandomWords(1, 5));
    _questions.addAll(_getRandomWords(2, 5));
    _questions.addAll(_getRandomWords(3, 5));
    _questions.addAll(_getRandomWords(4, 5));
    _questions.addAll(_getRandomWords(5, 10));

    _questions.shuffle();
    _testTypes = List.generate(_questions.length, (_) => LevelTestType.values[Random().nextInt(LevelTestType.values.length)]);
    
    Hive.box(DatabaseService.sessionBoxName).delete('level_test_session');
    _generateOptions();
    notifyListeners();
  }

  List<Word> _getRandomWords(int level, int count) {
    final allWords = DatabaseService.getWordsByLevel(level);
    final validWords = allWords.where((w) => 
      w.meaning.trim().isNotEmpty && 
      w.kanji.trim().isNotEmpty && 
      w.kana.trim().isNotEmpty
    ).toList();
    if (validWords.isEmpty) return [];
    validWords.shuffle();
    return validWords.take(count).toList();
  }

  void _generateOptions() {
    if (currentWord == null || currentType == null) return;
    
    String correct;
    switch (currentType!) {
      case LevelTestType.kanjiToMeaning: correct = currentWord!.meaning; break;
      case LevelTestType.meaningToKanji: correct = currentWord!.kanji; break;
      case LevelTestType.meaningToKana: correct = currentWord!.kana; break;
    }

    final allWords = DatabaseService.getWordsByLevel(currentWord!.level);
    Set<String> distractors = {};
    var pool = allWords.where((w) => w.meaning.isNotEmpty && w.kanji.isNotEmpty).toList()..shuffle();

    for (var w in pool) {
      if (distractors.length >= 3) break;
      String val;
      switch (currentType!) {
        case LevelTestType.kanjiToMeaning: val = w.meaning; break;
        case LevelTestType.meaningToKanji: val = w.kanji; break;
        case LevelTestType.meaningToKana: val = w.kana; break;
      }
      if (val != correct && val.trim().isNotEmpty) distractors.add(val);
    }

    _currentOptions = [correct, ...distractors];
    _currentOptions.shuffle();
  }

  void submitAnswer(String answer) {
    if (_isAnswered) return;
    _isAnswered = true;
    _selectedAnswer = answer;

    String correct;
    switch (currentType!) {
      case LevelTestType.kanjiToMeaning: correct = currentWord!.meaning; break;
      case LevelTestType.meaningToKanji: correct = currentWord!.kanji; break;
      case LevelTestType.meaningToKana: correct = currentWord!.kana; break;
    }

    if (answer == correct) {
      _totalCorrect++;
      _correctCountsPerLevel[currentWord!.level] = (_correctCountsPerLevel[currentWord!.level] ?? 0) + 1;
    }
    _saveSession();
    notifyListeners();
  }

  void nextQuestion() {
    if (_currentIndex < _questions.length - 1) {
      _currentIndex++;
      _isAnswered = false;
      _selectedAnswer = null;
      _generateOptions();
      _saveSession();
    } else {
      _isFinished = true;
      _saveResult();
    }
    notifyListeners();
  }

  void _saveSession() {
    if (_isFinished) {
      Hive.box(DatabaseService.sessionBoxName).delete('level_test_session');
      return;
    }
    
    final session = {
      'currentIndex': _currentIndex,
      'totalCorrect': _totalCorrect,
      'correctCountsPerLevel': _correctCountsPerLevel,
      // [수정] Word 객체의 원본 데이터를 모두 보존하도록 toJson 활용
      'questions': _questions.map((w) => {
        'id': w.id,
        'kanji': w.kanji,
        'kana': w.kana,
        'meaning': w.meaning,
        'level': w.level,
        'pronunciation': w.koreanPronunciation,
        'example_sentence': w.example_sentence,
      }).toList(),
      'testTypes': _testTypes.map((t) => t.index).toList(),
      'updatedAt': DateTime.now().toIso8601String(),
    };
    Hive.box(DatabaseService.sessionBoxName).put('level_test_session', session);
  }

  void resumeTest() {
    final box = Hive.box(DatabaseService.sessionBoxName);
    final dynamic sessionRaw = box.get('level_test_session');
    if (sessionRaw == null) {
      initTest();
      return;
    }

    final Map<String, dynamic> session = Map<String, dynamic>.from(sessionRaw);

    _currentIndex = session['currentIndex'] ?? 0;
    _totalCorrect = session['totalCorrect'] ?? 0;
    
    final dynamic rawLevelCounts = session['correctCountsPerLevel'];
    _correctCountsPerLevel.clear();
    if (rawLevelCounts is Map) {
      rawLevelCounts.forEach((key, value) {
        _correctCountsPerLevel[int.parse(key.toString())] = int.parse(value.toString());
      });
    }

    // [핵심 수정] 단어 데이터 복구 시 필드 매핑 강화
    final List<dynamic> rawQuestions = session['questions'];
    _questions = rawQuestions.map((j) {
      final q = Map<String, dynamic>.from(j);
      return Word(
        id: q['id'] ?? 0,
        kanji: q['kanji'] ?? '',
        kana: q['kana'] ?? '',
        meaning: q['meaning'] ?? '',
        level: q['level'] ?? 5,
        koreanPronunciation: q['pronunciation'] ?? '',
        example_sentence: q['example_sentence'] ?? '',
      );
    }).toList();
    
    final List<dynamic> rawTypes = session['testTypes'];
    _testTypes = rawTypes.map((i) => LevelTestType.values[i as int]).toList();
    
    _isFinished = false;
    _isAnswered = false;
    _selectedAnswer = null;
    
    if (_questions.isEmpty) {
      initTest();
    } else {
      _generateOptions();
      notifyListeners();
    }
  }

  String _calculateResult() {
    if (_totalCorrect >= 25) return 'N1';
    if (_totalCorrect >= 20) return 'N2';
    if (_totalCorrect >= 15) return 'N3';
    if (_totalCorrect >= 10) return 'N4';
    return 'N5';
  }

  void _saveResult() {
    final result = _calculateResult();
    final box = Hive.box(DatabaseService.sessionBoxName);
    box.put('recommended_level', result);
    box.delete('level_test_session');
  }

  String get recommendedLevel => _calculateResult();
  int get totalCorrect => _totalCorrect;
}
