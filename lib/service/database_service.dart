import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../model/word.dart';
import 'supabase_service.dart';

class DatabaseService {
  static const String boxName = 'wordsBox';
  static const String sessionBoxName = 'sessionBox';

  static Future<void> init() async {
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(WordAdapter());
    }
    await Hive.openBox<Word>(boxName);
    final sessionBox = await Hive.openBox(sessionBoxName);

    final dynamic recLevel = sessionBox.get('recommended_level');
    if (recLevel != null && recLevel is! String) {
      await sessionBox.put('recommended_level', recLevel.toString());
    }

    if (sessionBox.get('recommended_level') == 'N5 미만') {
      await sessionBox.put('recommended_level', 'N5');
    }
    debugPrint("📦 로컬 데이터베이스(Hive) 초기화 완료");
  }

  static Future<void> syncMasterData() async {
    final sessionBox = Hive.box(sessionBoxName);
    final wordsBox = Hive.box<Word>(boxName);

    try {
      final config = await SupabaseService.getAppConfig();
      if (config == null) return;

      final double remoteVersion = double.tryParse(config['data_version']?.toString() ?? '0.0') ?? 0.0;
      final double localVersion = double.tryParse(sessionBox.get('master_data_version', defaultValue: 0.0).toString()) ?? 0.0;

      if (remoteVersion > localVersion) {
        debugPrint("🆕 새로운 단어 데이터 버전 발견! (v$remoteVersion) 업데이트를 시작합니다...");
        final List<Word> remoteWords = await SupabaseService.fetchAllWords();
        if (remoteWords.isEmpty) return;

        for (var remoteWord in remoteWords) {
          final String key = '${remoteWord.level}_${remoteWord.id}';
          final localWord = wordsBox.get(key);
          
          if (localWord != null) {
            final updatedWord = Word(
              id: remoteWord.id,
              kanji: remoteWord.kanji,
              kana: remoteWord.kana,
              koreanPronunciation: remoteWord.koreanPronunciation,
              meaning: remoteWord.meaning,
              level: remoteWord.level,
              example_sentence: remoteWord.example_sentence,
              is_bookmarked: localWord.is_bookmarked,
              correct_count: localWord.correct_count,
              incorrect_count: localWord.incorrect_count,
              is_memorized: localWord.is_memorized,
              srs_stage: localWord.srs_stage,
              next_review_at: localWord.next_review_at,
              is_wrong_note: localWord.is_wrong_note,
              status: localWord.status,
            );
            await wordsBox.put(key, updatedWord);
          } else {
            await wordsBox.put(key, remoteWord);
          }
        }
        await sessionBox.put('master_data_version', remoteVersion);
        debugPrint("✅ 단어 마스터 데이터 업데이트 완료 (v$remoteVersion)");
      } else {
        debugPrint("✅ 최신 버전의 단어 데이터를 사용 중입니다.");
      }
    } catch (e) {
      debugPrint("❌ 단어 데이터 동기화 중 오류 발생: $e");
    }
  }

  static Future<void> loadJsonToHive(int level) async {
    final sessionBox = Hive.box(sessionBoxName);
    if (sessionBox.get('level_${level}_loaded', defaultValue: false) == true) {
      return;
    }

    var box = Hive.box<Word>(boxName);
    try {
      debugPrint("⏳ Level $level 최초 데이터 로드 중...");
      String fileName;
      if (level == 11) fileName = 'hiragana.json';
      else if (level == 12) fileName = 'katakana.json';
      else fileName = 'n$level.json';

      final String response = await rootBundle.loadString('assets/data/$fileName');
      final Map<String, Word> wordMap = await compute(_parseWords, {'jsonString': response, 'level': level});
      await box.putAll(wordMap);
      
      await sessionBox.put('level_${level}_loaded', true);
      debugPrint("✅ Level $level 로드 성공!");
    } catch (e) {
      debugPrint("❌ Level $level 데이터 로드 실패: $e");
    }
  }

  static Map<String, Word> _parseWords(Map<String, dynamic> params) {
    final String jsonString = params['jsonString'];
    final int level = params['level'];
    final Map<String, dynamic> data = json.decode(jsonString);
    final List<dynamic> vocabulary = data['vocabulary'];

    Map<String, Word> wordMap = {};
    for (var item in vocabulary) {
      final word = Word.fromJson(item, level: level);
      wordMap['${level}_${word.id}'] = word;
    }
    return wordMap;
  }

  static bool needsInitialLoading() => Hive.box<Word>(boxName).isEmpty;

  static List<Word> getWordsByLevel(int level) {
    var box = Hive.box<Word>(boxName);
    return box.values.where((w) => w.level.toString() == level.toString()).toList();
  }
}
