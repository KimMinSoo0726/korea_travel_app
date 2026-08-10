import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/message.dart';
import '../../providers/api_provider.dart';
import '../../providers/chat_provider.dart';
import 'widgets/chat_input.dart';
import 'widgets/message_bubble.dart';
import '../settings/trip_settings_bar.dart';
import '../../models/bookmark.dart';
import '../../providers/bookmark_provider.dart';
import '../../models/bookmark_request.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String? conversationId;
  final void Function(String id) onConversationCreated;


  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.onConversationCreated,
  });

  @override
  ConsumerState<ChatScreen> createState() => ChatScreenState();
}

class ChatScreenState extends ConsumerState<ChatScreen> {
  
  final _scrollController = ScrollController();
  final List<Message> _messages = [];
  final Set<String> _enriching = {}; 

  final _settingsKey = GlobalKey<TripSettingsBarState>();

  String? _convId;
  bool _loading = false;
  bool _sending = false;
  String? _error;

  bool _compareMode = false;              // Qwen 켜짐 여부
  final List<Message> _qwenMessages = []; // Qwen 응답 (비교용, 저장 안 함)
  bool _qwenLoading = false;


  void scrollToMessage(String? id) => _scrollToMessage(id);      // 노출
  void insertBookmark(Bookmark b) => _insertBookmarkInChat(b);  


  @override
  void initState() {
    super.initState();
    _convId = widget.conversationId;
    if (_convId != null) _loadMessages();
  }
  /// [immediate] true면 애니메이션 없이 즉시 이동
  void _scrollToBottom({bool immediate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      if (immediate) {
        _scrollController.jumpTo(max);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
        });
      } else {
        _scrollController.animateTo(
          max,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _loadMessages() async {
    
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ref.read(apiServiceProvider).listMessages(_convId!);
      if (!mounted) return;
      setState(() {
        _messages.clear();
        _qwenMessages.clear();

        for (final m in list) {
          if (m.role == MessageRole.user) {
            _messages.add(m);
            if (_hasQwenData(list)) _qwenMessages.add(m);   // 양쪽에
          } else if (m.isQwen) {
            _qwenMessages.add(m);
          } else {
            _messages.add(m);
          }
        }
        // Qwen 메시지가 있으면 비교 모드 자동 켜기
        if (_qwenMessages.isNotEmpty) _compareMode = true;
      });
      _scrollToBottom(immediate: true);

  // 미보강 Gemini 플랜 재시도
      for (final m in _messages) {
        if (m.isPlan && !m.enriched && m.isGemini) _enrichMessage(m.id);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
     /* Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) _scrollToBottom(immediate: true);
      });

      for (final m in list) {
        if (m.isPlan && !m.enriched) _enrichMessage(m.id);
      }

    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }*/
  }

  
  bool _hasQwenData(List<Message> list) =>
      list.any((m) => m.isQwen);
      
  Future<void> _send(String text) async {
    if (text.trim().isEmpty || _sending) return;
    final fullMessage = _buildMessageWithContext(text);
    final pending = Message.pending(text);

    setState(() {
      _sending = true;
      _messages.add(Message(
        id: 'local-${DateTime.now().microsecondsSinceEpoch}',
        role: MessageRole.user, text: text, createdAt: DateTime.now(),
      ));
      if (_compareMode) {
        _qwenMessages.add(Message(
          id: 'qu-${DateTime.now().microsecondsSinceEpoch}',
          role: MessageRole.user, text: text, createdAt: DateTime.now(),
        ));
        _qwenLoading = true;
      }
      _attachedBookmarks.clear();
    });
    _scrollToBottom();

    try {
      // ① Gemini 먼저 → convId 확보
      final res = await ref.read(apiServiceProvider).chat(
            conversationId: _convId,
            message: fullMessage,
          );
      if (!mounted) return;

      final convId = res.conversationId;
      if (_convId == null) {
        _convId = convId;
        widget.onConversationCreated(convId);
      }

      setState(() {
        final i = _messages.indexWhere((m) => m.id == pending.id);
        if (i >= 0) _messages[i] = res.userMessage;
        _messages.add(res.aiMessage);
      });
      _scrollToBottom();

      // ② convId 확정 후 Qwen 호출 → 저장 보장
      if (_compareMode) {
        _sendToQwen(convId, fullMessage);
      }

      if (res.needsEnrich) _enrichMessage(res.aiMessage.id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(Message(
          id: 'err-${DateTime.now().microsecondsSinceEpoch}',
          role: MessageRole.assistant,
          text: '⚠️ 전송에 실패했습니다: $e',
          createdAt: DateTime.now(),
        ));
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendToQwen(String conversationId, String message) async {
    setState(() => _qwenLoading = true);
    try {
      final r = await ref.read(apiServiceProvider).chatQwen(
            conversationId: conversationId,     // ★ 확정된 convId
            message: message,
          );
      if (!mounted) return;
      setState(() {
        _qwenMessages.add(Message(
          id: 'qa-${DateTime.now().microsecondsSinceEpoch}',
          role: MessageRole.assistant,
          text: r.text,
          createdAt: DateTime.now(),
          planJson: r.planJson,
          model: 'qwen',
        ));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _qwenMessages.add(Message(
          id: 'qe-${DateTime.now().microsecondsSinceEpoch}',
          role: MessageRole.assistant,
          text: '⚠️ Qwen 응답 실패: $e',
          createdAt: DateTime.now(),
          model: 'qwen',
        ));
      });
    } finally {
      if (mounted) setState(() => _qwenLoading = false);
    }
  }

 @override
  void didUpdateWidget(ChatScreen old) {
    super.didUpdateWidget(old);
    if (old.conversationId != widget.conversationId) {
      _convId = widget.conversationId;
      if (_convId != null) {
        _loadMessages();
      } else {
        // 새 대화로 전환 — 초기화
        setState(() {
          _messages.clear();
          _qwenMessages.clear();
        });
      }
    }
  }
  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _enrichMessage(String messageId) async {
    setState(() => _enriching.add(messageId));
    try {
      final r = await ref.read(apiServiceProvider).enrichPlanMessage(messageId);
      if (!mounted || r.planJson == null) return;
      setState(() {
        final i = _messages.indexWhere((m) => m.id == messageId);
        if (i >= 0) {
          _messages[i] =
              _messages[i].copyWith(planJson: r.planJson, enriched: true);
        }
      });
      if (mounted && r.total > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('장소 정보 ${r.matched}/${r.total}곳 적용 완료'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('보강 실패: $e');
    } finally {
      if (mounted) setState(() => _enriching.remove(messageId));
    }
  }

   @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    return Column(
      children: [
        TripSettingsBar(
          key: _settingsKey,
          conversationId: _convId,
          hasStarted: _messages.any((m) => m.isPlan),
          onApply: _send,
          onJumpToBookmark: _scrollToMessage,
          onInsertBookmark: _insertBookmarkInChat,
        ),
          // ★ PC + 비교 토글 바
        if (isWide) _compareToggleBar(),

        Expanded(child: (isWide && _compareMode)
              ? Row(
                  children: [
                    // 왼쪽 — Gemini
                    Expanded(child: _modelColumn('Gemini', _buildBody())),
                    Container(width: 1, color: Colors.grey.shade200),
                    // 오른쪽 — Qwen
                    Expanded(child: _modelColumn('Qwen 3.6', _buildQwenBody())),
                  ],
                )
              : _buildBody()),
        if (_sending) const _TypingIndicator(),
        if (_attachedBookmarks.isNotEmpty) _attachmentBar(),
        ChatInput(enabled: !_sending, onSend: _send),
      ],
    );
  }


Widget _compareToggleBar() {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Colors.grey.shade50,
      child: Row(
        children: [
          Icon(Icons.compare_arrows, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Text('모델 비교 (Qwen 3.6)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const Spacer(),
          Switch(
            value: _compareMode,
            onChanged: (v) => setState(() {
              _compareMode = v;
              if (!v) _qwenMessages.clear();   // 끄면 Qwen 내용 비움
            }),
          ),
        ],
      ),
    );
  }

   Widget _modelColumn(String label, Widget body) {
    final theme = Theme.of(context);
    final isQwen = label.startsWith('Qwen');
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8),
          color: isQwen
              ? Colors.orange.shade50
              : theme.colorScheme.primary.withOpacity(0.06),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isQwen
                      ? Colors.orange.shade800
                      : theme.colorScheme.primary)),
        ),
        Expanded(child: body),
      ],
    );
  }

   Widget _buildQwenBody() {
    if (_qwenMessages.isEmpty && !_qwenLoading) {
      return Center(
        child: Text('Qwen 응답이 여기 표시됩니다',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: _qwenMessages.length + (_qwenLoading ? 1 : 0),
      itemBuilder: (_, i) {
        if (i >= _qwenMessages.length) {
          return const Padding(
            padding: EdgeInsets.only(left: 24, bottom: 8),
            child: Row(children: [
              SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 12),
              Text('Qwen 작성 중...', style: TextStyle(fontSize: 12)),
            ]),
          );
        }
        final msg = _qwenMessages[i];
        // ★ 저장·북마크·보강 콜백 없이, 표시 전용 MessageBubble
        return MessageBubble(
          message: msg,
          conversationId: null,       // 저장 안 함
          isEnriching: false,
          onReplan: (_) {},           // 비활성
          // onBookmark 안 넘김 → 북마크 버튼 없음
        );
      },
    );
  }

  // ★ _buildBody 는 build와 다른 "메서드" — build가 아님
  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('불러오지 못했습니다',
                style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            TextButton(onPressed: _loadMessages, child: const Text('다시 시도')),
          ],
        ),
      );
    }
    if (_messages.isEmpty) return const _EmptyState();

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: _messages.length,
      itemBuilder: (_, i) {
        final msg = _messages[i];
        return Container(
          key: _keyFor(msg.id),
          child: MessageBubble(
            message: msg,
            conversationId: _convId,
            isEnriching: _enriching.contains(msg.id),
            onReplan: _send,
            onBookmark: _addBookmarkFromMessage,
          ),
        );
      },
    );
  }
  // 메시지 id → 위젯 key (스크롤 이동용)
  final Map<String, GlobalKey> _messageKeys = {};
  // 대화에 삽입된 북마크 (B안)
  final List<Bookmark> _pinnedInChat = [];

  GlobalKey _keyFor(String messageId) =>
      _messageKeys.putIfAbsent(messageId, () => GlobalKey());

  /// 북마크 → 해당 메시지로 스크롤
  void _scrollToMessage(String? messageId) {
    if (messageId == null) return;
    final key = _messageKeys[messageId];
    final ctx = key?.currentContext;
    if (ctx == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('원본 메시지를 찾을 수 없어요')),
      );
      return;
    }
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      alignment: 0.1,
    );
  }

  void _insertBookmarkInChat(Bookmark b) {
    _attachBookmark(b);                          // ★ 입력창에 첨부
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${b.label} 첨부됨 — 이어서 요청을 입력하세요'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _addBookmarkFromMessage(BookmarkRequest req) async {
    if (_convId == null) return;
    final b = await ref.read(bookmarkActionsProvider).add(
          conversationId: _convId!,
          type: req.type,
          label: req.label,
          messageId: req.messageId,
          place: req.place,
          itinerary: req.itinerary,
        );
    if (mounted && b != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('북마크에 추가했어요: ${b.label}')),
      );
    }
  }

  // 다음 메시지에 첨부할 북마크
  final List<Bookmark> _attachedBookmarks = [];

  void _attachBookmark(Bookmark b) {
    setState(() {
      _attachedBookmarks.removeWhere((x) => x.id == b.id);
      _attachedBookmarks.add(b);
    });
  }

  void _removeAttached(String id) {
    
    setState(() => _attachedBookmarks.removeWhere((x) => x.id == id));
  }

  /// 첨부된 북마크를 프롬프트 앞부분에 붙여서 전송
  String _buildMessageWithContext(String userText) {
    final parts = <String>[];

      // 대화 전 설정 변경분 (첫 질문 시)
    final st = _settingsKey.currentState;
    if (_convId == null && st != null && st.isDirty) {
      parts.add(st.currentSettings.toPromptMessage().trim());
    }
   // 첨부 북마크
    if (_attachedBookmarks.isNotEmpty) {
      final b = StringBuffer('[참고할 북마크]\n');
      for (final bm in _attachedBookmarks) {
        if (bm.isPlace && bm.place != null) {
          final p = bm.place!;
          b.writeln('- 장소: ${p.name}'
              '${p.placeType != null ? " (${p.placeType})" : ""}'
              '${p.address != null ? " / ${p.address}" : ""}');
        } else if (bm.isItinerary && bm.itinerary != null) {
          b.writeln('- 일정: ${bm.itinerary!.title}');
        }
      }
      parts.add(b.toString().trim());
    }

    parts.add(userText);
    return parts.join('\n\n');
  }

  Widget _attachmentBar() {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      color: theme.colorScheme.primary.withOpacity(0.04),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('첨부된 북마크 — 메시지와 함께 전달돼요',
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: _attachedBookmarks.map((b) {
              return Chip(
                avatar: Icon(b.isPlace ? Icons.place : Icons.map,
                    size: 14, color: theme.colorScheme.primary),
                label: Text(b.label, style: const TextStyle(fontSize: 12)),
                onDeleted: () => _removeAttached(b.id),
                deleteIcon: const Icon(Icons.close, size: 14),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.travel_explore, size: 64, color: Color(0xFF2E7D6B)),
          const SizedBox(height: 16),
          Text('어디로 떠나고 싶으세요?',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('예) "다음 주에 서울에서 부산으로 2박 3일 가족여행"',
              style: TextStyle(color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}


class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 24, bottom: 8),
      child: Row(
        children: [
          const SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 12),
          Text('여행 플래너가 작성 중... (장소 확인에 시간이 걸릴 수 있어요)',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ],
      ),
    );
  }
}

class _PinnedBookmarkCard extends StatelessWidget {
  final Bookmark bookmark;
  final VoidCallback onJump;
  final VoidCallback onRemove;

  const _PinnedBookmarkCard({
    required this.bookmark,
    required this.onJump,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = bookmark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.05),
        border: Border.all(
            color: theme.colorScheme.primary.withOpacity(0.3),
            style: BorderStyle.solid),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.push_pin, size: 14, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text('북마크',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary)),
              const Spacer(),
              InkWell(
                onTap: onRemove,
                child: Icon(Icons.close, size: 15, color: Colors.grey.shade400),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(b.isPlace ? Icons.place : Icons.map,
                  size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(b.label,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          if (b.isPlace && b.place?.address != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 22),
              child: Text(b.place!.address!,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ),
          if (b.isItinerary && b.itinerary != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 22),
              child: Text(
                  '${b.itinerary!.destination} · ${b.itinerary!.duration}일 · ${b.itinerary!.dayCount}일차 일정',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ),
          if (b.messageId != null) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: onJump,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.my_location,
                      size: 13, color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                  Text('원본 메시지로 이동',
                      style: TextStyle(
                          fontSize: 11.5, color: theme.colorScheme.primary)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}