import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/bookmark.dart';
import 'api_provider.dart';

/// 대화별 북마크 목록
final bookmarksProvider =
    FutureProvider.family<List<Bookmark>, String>((ref, conversationId) async {
  if (conversationId.isEmpty) return [];
  return ref.watch(apiServiceProvider).listBookmarks(conversationId);
});

final bookmarkActionsProvider =
    Provider((ref) => BookmarkActions(ref));

class BookmarkActions {
  final Ref ref;
  BookmarkActions(this.ref);

  Future<Bookmark?> add({
    required String conversationId,
    required String type,
    required String label,
    String? messageId,
    BookmarkPlace? place,
    BookmarkItinerary? itinerary,
    String? planId,
  }) async {
    final b = await ref.read(apiServiceProvider).addBookmark(
          conversationId: conversationId,
          type: type,
          label: label,
          messageId: messageId,
          place: place,
          itinerary: itinerary,
          planId: planId,
        );
    ref.invalidate(bookmarksProvider(conversationId));
    return b;
  }

  Future<void> remove(String conversationId, String bookmarkId) async {
    await ref.read(apiServiceProvider).deleteBookmark(bookmarkId);
    ref.invalidate(bookmarksProvider(conversationId));
  }
}