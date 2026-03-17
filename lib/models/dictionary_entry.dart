import 'package:hive/hive.dart';

part 'dictionary_entry.g.dart';

@HiveType(typeId: 0)
class DictionaryEntry extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String misheardWord;

  @HiveField(2)
  String correctWord;

  DictionaryEntry({
    required this.id,
    required this.misheardWord,
    required this.correctWord,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'misheardWord': misheardWord,
        'correctWord': correctWord,
      };

  factory DictionaryEntry.fromJson(Map<String, dynamic> json) =>
      DictionaryEntry(
        id: json['id'] as String,
        misheardWord: json['misheardWord'] as String,
        correctWord: json['correctWord'] as String,
      );
}
