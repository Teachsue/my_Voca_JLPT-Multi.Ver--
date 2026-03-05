import 'package:hive/hive.dart';

part 'word.g.dart';

@HiveType(typeId: 1)
class Word extends HiveObject {
  @HiveField(0)
  final int id;
  @HiveField(1)
  final String kanji;
  @HiveField(2)
  final String kana;
  @HiveField(3)
  final String koreanPronunciation;
  @HiveField(4)
  final String meaning;
  @HiveField(5)
  final int level;

  @HiveField(6)
  int correctCount;
  @HiveField(7)
  int incorrectCount;
  @HiveField(8)
  bool isMemorized;
  @HiveField(9)
  bool isBookmarked;
  @HiveField(10)
  int srsStage;
  @HiveField(11)
  DateTime? nextReviewDate;

  @HiveField(12)
  bool isWrongNote; // [추가] 오답노트 포함 여부

  Word({
    required this.id,
    required this.kanji,
    required this.kana,
    required this.koreanPronunciation,
    required this.meaning,
    required this.level,
    this.correctCount = 0,
    this.incorrectCount = 0,
    this.isMemorized = false,
    this.isBookmarked = false,
    this.srsStage = 0,
    this.nextReviewDate,
    this.isWrongNote = false,
  });

  factory Word.fromJson(Map<String, dynamic> json, {int? level}) {
    // level이 json에 없을 경우 인자로 받은 값을 사용 (v1.1 호환용)
    final levelInt = (json['level'] as int?) ?? level ?? 0;
    
    return Word(
      id: (json['id'] as int?) ?? 0,
      kanji: (json['kanji'] as String?) ?? '',
      kana: (json['kana'] as String?) ?? '',
      koreanPronunciation: (json['korean_pronunciation'] as String?) ?? '',
      meaning: (json['meaning'] as String?) ?? '',
      level: levelInt,
      correctCount: (json['correct_count'] as int?) ?? 0,
      incorrectCount: (json['incorrect_count'] as int?) ?? 0,
      isMemorized: (json['is_memorized'] as bool?) ?? false,
      isBookmarked: (json['is_bookmarked'] as bool?) ?? false,
      srsStage: (json['srs_stage'] as int?) ?? 0,
      nextReviewDate: json['next_review_date'] != null ? DateTime.parse(json['next_review_date']) : null,
      isWrongNote: (json['is_wrong_note'] as bool?) ?? false,
    );
  }
}
