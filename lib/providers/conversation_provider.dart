import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/conversation.dart';
import 'api_provider.dart';
import 'auth_provider.dart';

final conversationsProvider =
    FutureProvider<List<Conversation>>((ref) async {
  final uid = ref.watch(uidProvider);
  if (uid == null) return [];
  return ref.watch(apiServiceProvider).listConversations();
});