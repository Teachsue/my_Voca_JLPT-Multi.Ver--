// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'word.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class WordAdapter extends TypeAdapter<Word> {
  @override
  final int typeId = 1;

  @override
  Word read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Word(
      id: int.tryParse(fields[0]?.toString() ?? '0') ?? 0,
      kanji: fields[1]?.toString() ?? '',
      kana: fields[2]?.toString() ?? '',
      koreanPronunciation: fields[3]?.toString() ?? '',
      meaning: fields[4]?.toString() ?? '',
      level: int.tryParse(fields[5]?.toString() ?? '0') ?? 0,
      example_sentence: fields[13]?.toString(),
      correct_count: int.tryParse(fields[6]?.toString() ?? '0') ?? 0,
      incorrect_count: int.tryParse(fields[7]?.toString() ?? '0') ?? 0,
      is_memorized: fields[8] == true || fields[8]?.toString() == 'true',
      is_bookmarked: fields[9] == true || fields[9]?.toString() == 'true',
      srs_stage: int.tryParse(fields[10]?.toString() ?? '0') ?? 0,
      next_review_at: fields[11] is DateTime ? fields[11] as DateTime : (fields[11] != null ? DateTime.tryParse(fields[11].toString()) : null),
      is_wrong_note: fields[12] == true || fields[12]?.toString() == 'true',
      status: fields[14]?.toString() ?? 'unlearned',
    );
  }

  @override
  void write(BinaryWriter writer, Word obj) {
    writer
      ..writeByte(15)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.kanji)
      ..writeByte(2)
      ..write(obj.kana)
      ..writeByte(3)
      ..write(obj.koreanPronunciation)
      ..writeByte(4)
      ..write(obj.meaning)
      ..writeByte(5)
      ..write(obj.level)
      ..writeByte(13)
      ..write(obj.example_sentence)
      ..writeByte(6)
      ..write(obj.correct_count)
      ..writeByte(7)
      ..write(obj.incorrect_count)
      ..writeByte(8)
      ..write(obj.is_memorized)
      ..writeByte(9)
      ..write(obj.is_bookmarked)
      ..writeByte(10)
      ..write(obj.srs_stage)
      ..writeByte(11)
      ..write(obj.next_review_at)
      ..writeByte(12)
      ..write(obj.is_wrong_note)
      ..writeByte(14)
      ..write(obj.status);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WordAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
