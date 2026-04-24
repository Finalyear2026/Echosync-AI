class DictionaryEntry {

  String id;
  String misheardWord;
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
