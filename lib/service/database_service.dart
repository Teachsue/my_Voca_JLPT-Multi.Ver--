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

    // 구버전 데이터 보정: 'N5 미만' 기록이 있다면 'N5'로 변경
    if (sessionBox.get('recommended_level') == 'N5 미만') {
      await sessionBox.put('recommended_level', 'N5');
    }

    // 서버와 마스터 데이터 동기화 시도 (비동기로 실행하여 앱 시작 지연 방지)
    syncMasterData();
  }

  /// 서버와 단어 마스터 데이터 동기화
  static Future<void> syncMasterData() async {
    final sessionBox = Hive.box(sessionBoxName);
    final wordsBox = Hive.box<Word>(boxName);

    try {
      // 1. 서버 설정 가져오기
      final config = await SupabaseService.getAppConfig();
      if (config == null) return;

      final double remoteVersion = double.parse(((config['data_version'] is int) 
          ? (config['data_version'] as int).toDouble() 
          : (config['data_version'] as double? ?? 0.0)).toStringAsFixed(1));
          
      final dynamic localRawVersion = sessionBox.get('master_data_version', defaultValue: 0.0);
      final double localVersion = double.parse(((localRawVersion is int) ? localRawVersion.toDouble() : (localRawVersion as double? ?? 0.0)).toStringAsFixed(1));

      debugPrint("📡 데이터 버전 체크: 로컬($localVersion) vs 서버($remoteVersion)");

      // 2. 버전이 다르면 업데이트 시작
      if (remoteVersion > localVersion) {
        debugPrint("🔄 새 버전 발견! 단어 동기화 시작...");
        
        final List<Word> remoteWords = await SupabaseService.fetchAllWords();
        if (remoteWords.isEmpty) return;

        // 3. 기존 학습 데이터 보존하며 업데이트
        for (var remoteWord in remoteWords) {
          // DatabaseService에서 사용하는 키 형식: '${level}_${id}'
          final String key = '${remoteWord.level}_${remoteWord.id}';
          final localWord = wordsBox.get(key);
          
          if (localWord != null) {
            // 이미 있는 단어라면 마스터 정보만 업데이트 (학습 기록 유지)
            final updatedWord = Word(
              id: remoteWord.id,
              kanji: remoteWord.kanji,
              kana: remoteWord.kana,
              koreanPronunciation: remoteWord.koreanPronunciation,
              meaning: remoteWord.meaning,
              level: remoteWord.level,
              isBookmarked: localWord.isBookmarked,
              correctCount: localWord.correctCount,
              incorrectCount: localWord.incorrectCount,
              isMemorized: localWord.isMemorized,
              srsStage: localWord.srsStage,
              nextReviewDate: localWord.nextReviewDate,
            );
            await wordsBox.put(key, updatedWord);
          } else {
            // 새 단어라면 추가 (새 단어의 키 생성)
            await wordsBox.put(key, remoteWord);
          }
        }

        // 4. 로컬 버전 갱신
        await sessionBox.put('master_data_version', remoteVersion);
        debugPrint("✅ 단어 동기화 완료 (버전 $remoteVersion)");
      }
    } catch (e) {
      debugPrint("❌ 동기화 중 오류 발생: $e");
    }
  }

  // 앱 최초 실행 시 JSON 데이터를 Hive DB로 옮기는 함수
  static Future<void> loadJsonToHive(int level) async {
    var box = Hive.box<Word>(boxName);

    // 해당 레벨의 단어 개수를 확인
    int existingCount = box.values.where((w) => w.level.toString() == level.toString()).length;
    
    // 히라가나/가타카나는 개수가 적으므로 체크 기준 완화 (기본 46자 이상이면 로드된 것으로 간주)
    int threshold = (level >= 11) ? 40 : 100;
    
    if (existingCount >= threshold) {
      debugPrint("✅ Level $level 데이터가 이미 존재합니다. (개수: $existingCount)");
      return;
    }

    debugPrint("⏳ Level $level 데이터를 로드 중...");
    try {
      String fileName;
      if (level == 11) {
        fileName = 'hiragana.json';
      } else if (level == 12) {
        fileName = 'katakana.json';
      } else {
        fileName = 'n$level.json';
      }

      final String response = await rootBundle.loadString('assets/data/$fileName');
      
      // 무거운 연산을 별도 Isolate에서 수행 (메인 스레드 프리징 방지)
      final Map<String, Word> wordMap = await compute(_parseWords, {'jsonString': response, 'level': level});
      
      await box.putAll(wordMap);
      debugPrint("✅ Level $level 로드 완료! (총 ${wordMap.length}단어)");
    } catch (e) {
      debugPrint("❌ 데이터 로드 에러 (Level $level): $e");
    }
  }

  // Isolate에서 실행될 파싱 함수
  static Map<String, Word> _parseWords(Map<String, dynamic> params) {
    final String jsonString = params['jsonString'];
    final int level = params['level'];
    
    final Map<String, dynamic> data = json.decode(jsonString);
    final List<dynamic> vocabulary = data['vocabulary'];

    Map<String, Word> wordMap = {};
    for (var item in vocabulary) {
      // JSON 데이터를 Word 객체로 변환
      final word = Word.fromJson(item);
      final fixedWord = Word(
        id: word.id,
        kanji: word.kanji,
        kana: word.kana,
        meaning: word.meaning,
        level: level,
        koreanPronunciation: word.koreanPronunciation,
      );
      wordMap['${level}_${fixedWord.id}'] = fixedWord;
    }
    return wordMap;
  }

  static bool needsInitialLoading() {
    var box = Hive.box<Word>(boxName);
    return box.isEmpty;
  }

  static List<Word> getWordsByLevel(int level) {
    var box = Hive.box<Word>(boxName);
    // 타입 불일치 방지를 위해 문자열로 변환하여 비교
    return box.values.where((w) => w.level.toString() == level.toString()).toList();
  }
}
