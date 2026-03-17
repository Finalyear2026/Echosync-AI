part of 'snippet.dart';

class SnippetAdapter extends TypeAdapter<Snippet> {
  @override
  final int typeId = 1;

  @override
  Snippet read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Snippet(
      id: fields[0] as String,
      triggerPhrase: fields[1] as String,
      templateContent: fields[2] as String,
      description: fields[3] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Snippet obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.triggerPhrase)
      ..writeByte(2)
      ..write(obj.templateContent)
      ..writeByte(3)
      ..write(obj.description);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SnippetAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
