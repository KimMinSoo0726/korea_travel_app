import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chat/chat_screen.dart';
import '../plans/plans_screen.dart';
import '../plans/plan_detail_screen.dart';
import 'widgets/app_drawer.dart';
import '../settings/preferences_screen.dart';

enum HomeTab { chat, plans,prefs }

class HomeShell extends ConsumerStatefulWidget {
  final String? conversationId;
  final String? planId;
  final HomeTab initialTab;
  const HomeShell({
    super.key,
    this.conversationId,
    this.planId,
    this.initialTab = HomeTab.chat,
  });

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  late HomeTab _tab;
  String? _convId;
  String? _planId;

  final _chatKey = GlobalKey<ChatScreenState>();

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    _convId = widget.conversationId;
    _planId = widget.planId;
  }

  void _openConversation(String? id) {
    setState(() {
      _tab = HomeTab.chat;
      _convId = id;
      _planId = null;
    });
    if (MediaQuery.of(context).size.width < 900) Navigator.of(context).maybePop();
  }

  void _openPlans() {
    setState(() {
      _tab = HomeTab.plans;
      _planId = null;
    });
    if (MediaQuery.of(context).size.width < 900) Navigator.of(context).maybePop();
  }

  void _openPlanDetail(String planId) {
    setState(() {
      _tab = HomeTab.plans;
      _planId = planId;
    });
  }
  void _openPrefs() {
    setState(() {
      _tab = HomeTab.prefs;
      _planId = null;
    });
    if (MediaQuery.of(context).size.width < 900) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;


    final drawer = AppDrawer(
    currentConversationId: _convId,
    onNewChat: () => _openConversation(null),
    onSelectConversation: _openConversation,
    onOpenPlans: _openPlans,
    onOpenPrefs: _openPrefs,
    onJumpToBookmark: (id) => _chatKey.currentState?.scrollToMessage(id),
    onInsertBookmark: (b) => _chatKey.currentState?.insertBookmark(b),
  );

/*
  ChatScreen(
    key: _chatKey,
    conversationId: _convId,
    onConversationCreated: (id) => setState(() => _convId = id),
  );

  */
    Widget body;
    if (_tab == HomeTab.chat) {
      body = ChatScreen(
       // key: ValueKey(_convId ?? 'new'),
        key: _chatKey,
        conversationId: _convId,
        onConversationCreated: (id) => setState(() => _convId = id),
      );
    } else if (_tab == HomeTab.prefs) {
      body = const PreferencesScreen();        
    } else {
      body = _planId == null
          ? PlansScreen(onOpenPlan: _openPlanDetail)
          : PlanDetailScreen(
              planId: _planId!,
              onBack: () => setState(() => _planId = null),
            );
    }

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            SizedBox(width: 280, child: Material(elevation: 1, child: drawer)),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_tab == HomeTab.chat
            ? '대화'
            : _tab == HomeTab.prefs
                ? '여행 취향'
                : '저장된 플랜'),
      ),
      drawer: Drawer(child: drawer),
      body: body,
    );
  }
}