part of 'dictionary_entry.dart';

class DictionaryEntryAdapter extends TypeAdapter<DictionaryEntry> {
  @override
  final int typeId = 0;

  @override
  DictionaryEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DictionaryEntry(
      id: fields[0] as String,
      misheardWord: fields[1] as String,
      correctWord: fields[2] as String,
    );
  }

  @override
  void write(BinaryWriter writer, DictionaryEntry obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.misheardWord)
      ..writeByte(2)
      ..write(obj.correctWord);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DictionaryEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
