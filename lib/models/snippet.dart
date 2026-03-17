import 'package:hive/hive.dart';

part 'snippet.g.dart';

@HiveType(typeId: 1)
class Snippet extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String triggerPhrase;

  @HiveField(2)
  String templateContent;

  @HiveField(3)
  String? description;

  Snippet({
    required this.id,
    required this.triggerPhrase,
    required this.templateContent,
    this.description,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'triggerPhrase': triggerPhrase,
        'templateContent': templateContent,
        'description': description,
      };

  factory Snippet.fromJson(Map<String, dynamic> json) => Snippet(
        id: json['id'] as String,
        triggerPhrase: json['triggerPhrase'] as String,
        templateContent: json['templateContent'] as String,
        description: json['description'] as String?,
      );
}
