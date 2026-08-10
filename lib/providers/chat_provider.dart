import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import 'api_provider.dart';
import 'conversation_provider.dart';

final chatControllerProvider = Provider((ref) => ChatController(ref));

class ChatController {
  final Ref ref;
  ChatController(this.ref);

  Future<ChatResult> send({String? convId, required String text}) async {
    final res =
        await ref.read(apiServiceProvider).chat(conversationId: convId, message: text);
    // 대화 목록 갱신 (제목/정렬 반영)
    ref.invalidate(conversationsProvider);
    return res;
  }
}