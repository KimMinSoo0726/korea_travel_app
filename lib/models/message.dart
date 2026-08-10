enum MessageRole { user, assistant }

class Message {
   final String id;
  final MessageRole role;
  final String text;
  final DateTime createdAt;
  final Map<String, dynamic>? planJson;
  final bool enriched;
  final String? model;       

  Message({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    this.planJson,
    this.enriched = false,
    this.model,
  });

  bool get isPlan => planJson != null;
  bool get isQwen => model == 'qwen';       // ★
  bool get isGemini => model == 'gemini';


 factory Message.fromMap(Map<String, dynamic> map) => Message(
        id: map['_id'] ?? '',
        role: map['role'] == 'user' ? MessageRole.user : MessageRole.assistant,
        text: map['text'] ?? '',
        createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
        planJson: map['planJson'] == null
            ? null
            : (map['planJson'] as Map).map((k, v) => MapEntry('$k', v)),
        enriched: map['enriched'] == true,
        model: map['model'],              
      );

    Message copyWith({Map<String, dynamic>? planJson, bool? enriched, String? model}) =>
      Message(
        id: id, role: role, text: text, createdAt: createdAt,
        planJson: planJson ?? this.planJson,
        enriched: enriched ?? this.enriched,
        model: model ?? this.model,
      );

  factory Message.pending(String text) => Message(
        id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
        role: MessageRole.user,
        text: text,
        createdAt: DateTime.now(),
      );
}