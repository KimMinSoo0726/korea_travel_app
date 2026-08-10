import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/message.dart';
import '../../../models/travel_plan.dart';
import 'plan_card.dart';
import '../../../models/bookmark_request.dart';


class MessageBubble extends StatelessWidget {
  final Message message;
  final String? conversationId;
  final bool isEnriching;
  final void Function(String replanText) onReplan;
  final void Function(BookmarkRequest req)? onBookmark;

  const MessageBubble({
    super.key,
    required this.message,
    required this.conversationId,
    this.isEnriching = false,
    required this.onReplan,
    this.onBookmark,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;

    // 플랜 응답
    if (message.isPlan && PlanOptions.isPlanOptions(message.planJson)) {
      final options = PlanOptions.fromJson(message.planJson!);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.text.isNotEmpty)
            _bubble(context, message.text, isUser: false),
          if (options.message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
              child: Text(options.message,
                  style: TextStyle(color: Colors.grey.shade700)),
            ),
          if (isEnriching) const _EnrichBanner(),
          ...options.plans.map(
            (plan) => PlanCard(
              plan: plan,
              conversationId: conversationId,
              isEnriching: isEnriching,
              messageId: message.id,   
              onReplan: onReplan,
              onBookmark: onBookmark, 
            ),
          ),
          const SizedBox(height: 8),
        ],
      );
    }

    // 일반 메시지
    return _bubble(context, message.text, isUser: isUser);
  }

   Widget _bubble(BuildContext context, String text, {required bool isUser}) {
    final theme = Theme.of(context);
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isUser ? theme.colorScheme.primary : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
          border: isUser ? null : Border.all(color: Colors.grey.shade200),
        ),
        child: isUser
            // 사용자 메시지 — 일반 텍스트
            ? SelectableText(
                text,
                style: const TextStyle(color: Colors.white, height: 1.4),
              )
            // AI 메시지 — 마크다운 렌더링
            : MarkdownBody(
                  data: text,
                  selectable: true,
                shrinkWrap: true, 
                  styleSheet: _markdownStyle(theme),
                  onTapLink: (txt, href, title) {
                    if (href != null) {
                      launchUrl(Uri.parse(href),
                          mode: LaunchMode.externalApplication);
                    }
                  },
                ),
      ),
    );
  }

  MarkdownStyleSheet _markdownStyle(ThemeData theme) {
    const dark = Color(0xFF1A1A1A);
    return MarkdownStyleSheet(
      p: const TextStyle(fontSize: 14, height: 1.5, color: dark),
      h1: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: dark),
      h2: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: dark),
      h3: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary),
      strong: const TextStyle(fontWeight: FontWeight.bold, color: dark),
      em: const TextStyle(fontStyle: FontStyle.italic, color: dark),
      listBullet: const TextStyle(fontSize: 14, color: dark),
      // 목록 간격
      listIndent: 20,
      blockSpacing: 8,
      // 코드/인용 (드물지만 대비)
      code: TextStyle(
        backgroundColor: Colors.grey.shade100,
        fontFamily: 'monospace',
        fontSize: 13,
      ),
      blockquote: TextStyle(color: Colors.grey.shade600),
      blockquoteDecoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(
            left: BorderSide(color: theme.colorScheme.primary, width: 3)),
      ),
    );
  }
}

class _EnrichBanner extends StatelessWidget {
  const _EnrichBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('장소 정보를 적용하는 중이에요',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary)),
                const SizedBox(height: 1),
                Text('주소·좌표·사진을 확인하고 있습니다 (최대 30초)',
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}