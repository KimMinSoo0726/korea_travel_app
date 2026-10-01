import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


import '../../../providers/auth_provider.dart';
import '../../../providers/conversation_provider.dart';
import '../../../providers/api_provider.dart';
import '../../settings/trip_settings_bar.dart';

import '../../../models/bookmark.dart';
import '../../../providers/bookmark_provider.dart';

class AppDrawer extends ConsumerWidget {
  final String? currentConversationId;
  final VoidCallback onNewChat;
  final void Function(String id) onSelectConversation;
  final VoidCallback onOpenPlans;
  final VoidCallback onOpenPrefs;   

  final void Function(String? messageId)? onJumpToBookmark;
  final void Function(Bookmark bookmark)? onInsertBookmark;

  const AppDrawer({
    super.key,
    required this.currentConversationId,
    required this.onNewChat,
    required this.onSelectConversation,
    required this.onOpenPlans,
    required this.onOpenPrefs,
    this.onJumpToBookmark,
    this.onInsertBookmark,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(conversationsProvider);
    final user = ref.watch(authStateProvider).value;

    return SafeArea(
      child: Column(
        children: [
          // 새 대화 버튼
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onNewChat,

                icon: const Icon(Icons.add),
                label: const Text('새 대화'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
           ListTile(
            leading: const Icon(Icons.bookmark_border),
            title: const Text('저장된 플랜'),
            onTap: onOpenPlans,
          ),
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('여행 취향 설정'),
            onTap: onOpenPrefs,
          ),
          const Divider(),
         Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text('대화 목록',
                  style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              InkWell(
                onTap: () => ref.invalidate(conversationsProvider),
                child: Icon(Icons.refresh, size: 16, color: Colors.grey.shade400),
              ),
            ],
          ),
        ),

        
          // 대화 리스트
          Expanded(
            flex:2,
            child: conversations.when(
              data: (list) => list.isEmpty
                  ? Center(
                      child: Text('대화가 없습니다',
                          style: TextStyle(color: Colors.grey.shade400)))
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final c = list[i];
                        final selected = c.id == currentConversationId;
                        return ListTile(
                          selected: selected,
                          selectedTileColor:
                              Theme.of(context).colorScheme.primary.withOpacity(0.08),
                          leading: const Icon(Icons.chat_bubble_outline, size: 20),
                          title: Text(c.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () => _confirmDelete(context, ref, c.id),
                          ),
                          onTap: () => onSelectConversation(c.id),
                        );
                      },
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('오류: $e')),
            ),
          ),
 // ★ 북마크 섹션 (대화가 있을 때만)
        if (currentConversationId != null)
          Expanded(
            flex: 2,
            child:  _BookmarkSection(
            conversationId: currentConversationId!,
            onJump: onJumpToBookmark,
            onInsert: onInsertBookmark,
            )
          )
         ,

          const Divider(height: 1),
          // 사용자 정보 + 로그아웃
          ListTile(
            leading: CircleAvatar(
              backgroundImage:
                  user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
              child: user?.photoURL == null ? const Icon(Icons.person) : null,
            ),
            title: Text(user?.displayName ?? '사용자',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(user?.email ?? '',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => ref.read(authServiceProvider).signOut(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, String convId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('대화 삭제'),
        content: const Text('이 대화를 삭제하시겠습니까?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('삭제')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(apiServiceProvider).deleteConversation(convId);
      ref.invalidate(conversationsProvider);
    }
  }
}



class _BookmarkSection extends ConsumerWidget {
  final String conversationId;
  final void Function(String? messageId)? onJump;
  final void Function(Bookmark)? onInsert;

  const _BookmarkSection({
    required this.conversationId,
    this.onJump,
    this.onInsert,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(bookmarksProvider(conversationId));
    final list = async.value ?? [];

    // 북마크 없으면 섹션 자체를 숨김
    if (list.isEmpty) return const SizedBox.shrink();

    final places = list.where((b) => b.isPlace).toList();
    final itins = list.where((b) => b.isItinerary).toList();

    return Container(
       constraints: const BoxConstraints(maxHeight: 240), 
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: SingleChildScrollView(
        child: Column(

          mainAxisSize: MainAxisSize.min,  
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Icon(Icons.bookmarks, size: 15, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Text('북마크',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade600)),
                ],
              ),
            ),

            // 일정 북마크
            if (itins.isNotEmpty)
              _group(context, '일정', Icons.map, itins),
            // 장소 북마크
            if (places.isNotEmpty)
              _group(context, '장소', Icons.place, places),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _group(
      BuildContext context, String title, IconData icon, List<Bookmark> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
          child: Text('$title ${items.length}',
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade400)),
        ),
        ...items.map((b) => _tile(context, b)),
      ],
    );
  }

  Widget _tile(BuildContext context, Bookmark b) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => onInsert?.call(b),      // 탭 = 대화에 첨부
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Icon(b.isPlace ? Icons.place : Icons.map,
                size: 14, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(b.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w500)),
                  if (b.isPlace && b.place?.address != null)
                    Text(b.place!.address!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 10.5, color: Colors.grey.shade400)),
                ],
              ),
            ),
            if (b.fromSavedPlan)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(Icons.push_pin,
                    size: 11, color: Colors.amber.shade600),
              ),
          ],
        ),
      ),
    );
  }
}