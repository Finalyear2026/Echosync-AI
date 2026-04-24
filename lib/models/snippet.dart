class Snippet {

  String id;
  String triggerPhrase;
  String templateContent;
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
