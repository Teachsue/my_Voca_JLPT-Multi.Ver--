import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../model/word.dart';
import 'supabase_service.dart';

class DatabaseService {
  static const String boxName = 'wordsBox';
  static const String sessionBoxName = 'sessionBox';

  // [중요] JSON 파일(오타, 예문 등)을 수정했을 때 이 버전을 올리면 
  // 기존 사용자들의 폰에서도 바뀐 내용이 강제 반영됩니다.
  static const double currentJsonVersion = 1.1;

  static Future<void> init() async {
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(WordAdapter());
    }
    await Hive.openBox<Word>(boxName);
    final sessionBox = await Hive.openBox(sessionBoxName);

    // --- JSON 버전 체크 및 강제 재로드 로직 ---
    final double lastJsonVersion = double.tryParse(sessionBox.get('last_json_version', defaultValue: 1.0).toString()) ?? 1.0;
    
    if (currentJsonVersion > lastJsonVersion) {
      debugPrint("🆕 로컬 JSON 데이터 버전 업그레이드 감지 (v$lastJsonVersion -> v$currentJsonVersion)");
      // 모든 레벨 로드 플래그를 삭제하여 다시 로드하게 함
      for (int i = 1; i <= 5; i++) {
        await sessionBox.delete('level_${i}_loaded');
      }
      await sessionBox.delete('level_11_loaded'); // 히라가나
      await sessionBox.delete('level_12_loaded'); // 가타카나
      
      // 버전 정보 갱신
      await sessionBox.put('last_json_version', currentJsonVersion);
      debugPrint("🧹 기존 로드 플래그 초기화 완료. 다음 부팅 시 최신 JSON을 병합합니다.");
    }

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

        Map<String, Word> updates = {};
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
            updates[key] = updatedWord;
          } else {
            updates[key] = remoteWord;
          }
        }
        
        if (updates.isNotEmpty) {
          await wordsBox.putAll(updates);
          debugPrint("💾 총 ${updates.length}개의 단어 정보가 로컬 DB에 반영되었습니다.");
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
      debugPrint("⏳ Level $level 데이터 동기화/로드 중...");
      String fileName;
      if (level == 11) fileName = 'hiragana.json';
      else if (level == 12) fileName = 'katakana.json';
      else fileName = 'n$level.json';

      final String response = await rootBundle.loadString('assets/data/$fileName');
      final Map<String, Word> wordMapFromContext = await compute(_parseWords, {'jsonString': response, 'level': level});
      
      // [스마트 머지] 기존 학습 데이터는 유지하고 단어 정보만 업데이트
      Map<String, Word> finalUpdates = {};
      for (var entry in wordMapFromContext.entries) {
        final String key = entry.key;
        final Word newWordInfo = entry.value;
        final Word? existingWord = box.get(key);

        if (existingWord != null) {
          // 이미 학습 기록이 있는 단어라면 '단어 본문'만 교체
          final updatedWord = Word(
            id: newWordInfo.id,
            kanji: newWordInfo.kanji,
            kana: newWordInfo.kana,
            koreanPronunciation: newWordInfo.koreanPronunciation,
            meaning: newWordInfo.meaning,
            level: newWordInfo.level,
            example_sentence: newWordInfo.example_sentence,
            // 아래는 기존 학습 데이터 보존
            is_bookmarked: existingWord.is_bookmarked,
            correct_count: existingWord.correct_count,
            incorrect_count: existingWord.incorrect_count,
            is_memorized: existingWord.is_memorized,
            srs_stage: existingWord.srs_stage,
            next_review_at: existingWord.next_review_at,
            is_wrong_note: existingWord.is_wrong_note,
            status: existingWord.status,
          );
          finalUpdates[key] = updatedWord;
        } else {
          // 처음 보는 단어라면 그대로 추가
          finalUpdates[key] = newWordInfo;
        }
      }

      if (finalUpdates.isNotEmpty) {
        await box.putAll(finalUpdates);
        debugPrint("💾 Level $level: ${finalUpdates.length}개의 단어가 최신 정보로 병합되었습니다.");
      }
      
      await sessionBox.put('level_${level}_loaded', true);
      debugPrint("✅ Level $level 로드 및 병합 성공!");
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
