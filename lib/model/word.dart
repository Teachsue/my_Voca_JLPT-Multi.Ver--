import 'package:hive/hive.dart';

part 'word.g.dart';

@HiveType(typeId: 1)
class Word extends HiveObject {
  // --- [1. words_master 영역] ---
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
  @HiveField(13)
  final String? example_sentence;

  // --- [2. user_progress 영역] ---
  @HiveField(6)
  int correct_count;
  @HiveField(7)
  int incorrect_count;
  @HiveField(8)
  bool is_memorized;
  @HiveField(9)
  bool is_bookmarked;
  @HiveField(10)
  int srs_stage;
  @HiveField(11)
  DateTime? next_review_at;
  @HiveField(12)
  bool is_wrong_note;
  @HiveField(14)
  String status; // 'unlearned', 'studying', 'mastered'

  Word({
    required this.id,
    required this.kanji,
    required this.kana,
    required this.koreanPronunciation,
    required this.meaning,
    required this.level,
    this.example_sentence,
    this.correct_count = 0,
    this.incorrect_count = 0,
    this.is_memorized = false,
    this.is_bookmarked = false,
    this.srs_stage = 0,
    this.next_review_at,
    this.is_wrong_note = false,
    this.status = 'unlearned',
  });

  factory Word.fromJson(Map<String, dynamic> json, {int? level}) {
    // level이 String으로 올 경우를 대비해 int.tryParse 적용
    int levelInt = level ?? 0;
    if (json['level'] != null) {
      if (json['level'] is int) {
        levelInt = json['level'];
      } else {
        levelInt = int.tryParse(json['level'].toString()) ?? levelInt;
      }
    }
    
    return Word(
      id: int.tryParse(json['id']?.toString() ?? json['word_id']?.toString() ?? '0') ?? 0,
      kanji: json['kanji']?.toString() ?? '',
      kana: json['kana']?.toString() ?? '',
      koreanPronunciation: json['korean_pronunciation']?.toString() ?? json['pronunciation']?.toString() ?? '',
      meaning: json['meaning']?.toString() ?? '',
      level: levelInt,
      example_sentence: json['example_sentence']?.toString(),
      
      correct_count: int.tryParse(json['correct_count']?.toString() ?? '0') ?? 0,
      incorrect_count: int.tryParse(json['incorrect_count']?.toString() ?? '0') ?? 0,
      is_memorized: json['is_memorized'] == true || json['is_memorized'] == 'true',
      is_bookmarked: json['is_bookmarked'] == true || json['is_bookmarked'] == 'true',
      srs_stage: int.tryParse(json['srs_stage']?.toString() ?? '0') ?? 0,
      next_review_at: json['next_review_at'] != null ? DateTime.tryParse(json['next_review_at'].toString()) : null,
      is_wrong_note: json['is_wrong_note'] == true || json['is_wrong_note'] == 'true',
      status: json['status']?.toString() ?? 'unlearned',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'word_id': id,
      'level': level,
      'correct_count': correct_count,
      'incorrect_count': incorrect_count,
      'is_memorized': is_memorized,
      'is_bookmarked': is_bookmarked,
      'is_wrong_note': is_wrong_note,
      'srs_stage': srs_stage,
      'next_review_at': next_review_at?.toIso8601String(),
      'status': status,
    };
  }
}
