import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/trip_settings.dart';
import '../../providers/api_provider.dart';
import '../../models/bookmark.dart';
import '../../providers/bookmark_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class TripSettingsBar extends ConsumerStatefulWidget {
  final String? conversationId;

  final bool hasStarted;    
  final void Function(String promptText) onApply;
  final void Function(String? messageId)? onJumpToBookmark;
  final void Function(Bookmark bookmark)? onInsertBookmark;

  const TripSettingsBar({
    super.key,
    required this.conversationId,
    this.hasStarted = false,    
    required this.onApply,
    this.onJumpToBookmark,
    this.onInsertBookmark,
  });

  @override
  ConsumerState<TripSettingsBar> createState() => TripSettingsBarState();
}

class TripSettingsBarState extends ConsumerState<TripSettingsBar> {
  TripSettings _settings = const TripSettings();
  bool _showOptions = false;
  bool _dirty = false;
  bool _loading = true;


  TripSettings get currentSettings => _settings;
  bool get isDirty => _dirty;
  
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(TripSettingsBar old) {
    super.didUpdateWidget(old);
    if (old.conversationId != widget.conversationId) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final s = await ref
          .read(apiServiceProvider)
          .getConversationSettings(widget.conversationId);
      if (mounted) setState(() => _settings = s);
    } catch (e) {
      debugPrint('설정 로드 실패: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 외부에서 대화 후 갱신용
  void reload() => _load();

  Future<void> _update(TripSettings s) async {
    setState(() {
      _settings = s;
      _dirty = true;
    });
    // ★ 대화별 설정만 저장 (기본 프로필은 건드리지 않음)
    if (widget.conversationId != null) {
      try {
        await ref
            .read(apiServiceProvider)
            .saveConversationSettings(widget.conversationId!, s);
      } catch (e) {
        debugPrint('대화 설정 저장 실패: $e');
      }
    }
    // conversationId가 null(새 대화 시작 전)이면 로컬 상태로만 유지
  }
    

  void _apply() {
    widget.onApply(_settings.toPromptMessage());
    setState(() {
      _dirty = false;
      _showOptions = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) return const SizedBox.shrink();

     final isMobile = MediaQuery.of(context).size.width < 900;

    final p = _settings.prefs;
    final t = _settings.trip;

    return Material(
      color: Colors.white,
      elevation: 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 한 줄 요약 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 8),
            
            child: Row(
              children: [
                Icon(Icons.tune, size: 15, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                // 스타일 배지 (기존)
                InkWell(
                  onTap: () => setState(() => _showOptions = !_showOptions),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(p.paceLabel,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.primary)),
                        const SizedBox(width: 3),
                        Icon(
                            _showOptions
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 14,
                            color: theme.colorScheme.primary),
                      ],
                    ),
                  ),
                ),
                // 관심사
                if (p.interests.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(p.interests.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11.5, color: Colors.grey.shade600)),
                  ),
                ],



                const Spacer(),
                // ★ 모바일에서만 북마크 드롭다운
                if (isMobile && widget.conversationId != null)
                  _BookmarkDropdown(
                    conversationId: widget.conversationId!,
                    onInsert: widget.onInsertBookmark,
                    onJump: widget.onJumpToBookmark,
                  ),
              ],
            ),
          ),

          // ── 대화에서 추출된 여행 정보 (읽기 전용) ──
          if (!t.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: SizedBox(
                height: 26,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    if (t.origin.isNotEmpty && t.destination.isNotEmpty)
                      _infoChip('🚩 ${t.origin} → ${t.destination}'),
                    if (t.startDate.isNotEmpty)
                      _infoChip('📅 ${t.startDate}'
                          '${t.duration > 0 ? " (${t.duration}일)" : ""}'),
                    if (t.arrivalTime.isNotEmpty)
                      _infoChip('🕐 도착 ${t.arrivalTime}'),
                    if (t.returnDeadline.isNotEmpty)
                      _infoChip('🏠 복귀 ${t.returnDeadline}'),
                    if (t.people > 0)
                      _infoChip('👥 ${t.people}명'
                          '${t.children > 0 ? " (아동 ${t.children})" : ""}'),
                    if (t.transport.isNotEmpty) _infoChip('🚌 ${t.transport}'),
                    if (t.budget.isNotEmpty && t.budget != '미지정')
                      _infoChip('💰 ${t.budget}'),
                  ],
                ),
              ),
            ),

          // ── 옵션 영역 ──
          if (_showOptions) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('여행 강도'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children:
                        TravelPreferences.paceOptions.entries.map((e) {
                      return ChoiceChip(
                        label:
                            Text(e.value, style: const TextStyle(fontSize: 12)),
                        selected: p.pace == e.key,
                        onSelected: (_) => _update(_settings.copyWith(
                            prefs: p.copyWith(pace: e.key))),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  _label('관심사'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children:
                        TravelPreferences.interestOptions.map((i) {
                      final sel = p.interests.contains(i);
                      return FilterChip(
                        label: Text(i, style: const TextStyle(fontSize: 12)),
                        selected: sel,
                        showCheckmark: false,
                        onSelected: (v) {
                          final list = [...p.interests];
                          v ? list.add(i) : list.remove(i);
                          _update(_settings.copyWith(
                              prefs: p.copyWith(interests: list)));
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  _label('계획 방식'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children:
                        TravelPreferences.planningOptions.entries.map((e) {
                      return ChoiceChip(
                        label: Text(
                            e.key == 'planned' ? '계획적' : '무계획',
                            style: const TextStyle(fontSize: 12)),
                        selected: p.planningMode == e.key,
                        onSelected: (_) => _update(_settings.copyWith(
                            prefs: p.copyWith(planningMode: e.key))),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],

          // ── 재요청 버튼 ──
         if (_dirty && widget.hasStarted)
            Container(
              width: double.infinity,
              color: theme.colorScheme.primary.withOpacity(0.06),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text('설정이 바뀌었어요. 이 조건으로 다시 추천받을까요?',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade700)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _apply,
                    icon: const Icon(Icons.auto_awesome, size: 15),
                    label:
                        const Text('다시 추천', style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      minimumSize: const Size(0, 34),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _label(String t) => Text(t,
      style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade500));

  Widget _infoChip(String text) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(text,
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700)),
        ),
      );
}

class _BookmarkMenuButton extends ConsumerWidget {
  final String conversationId;
  final void Function(String? messageId)? onJump;
  final void Function(Bookmark)? onInsert;

  const _BookmarkMenuButton({
    required this.conversationId,
    this.onJump,
    this.onInsert,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(bookmarksProvider(conversationId));
    final count = async.value?.length ?? 0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.bookmarks_outlined, size: 19),
          tooltip: '북마크',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          onPressed: () => _openSheet(context, ref),
        ),
        if (count > 0)
          Positioned(
            right: 2,
            top: 2,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                  color: Colors.redAccent, shape: BoxShape.circle),
              constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
              child: Text('$count',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 9)),
            ),
          ),
      ],
    );
  }

  void _openSheet(BuildContext context, WidgetRef ref) {
    final wide = MediaQuery.of(context).size.width >= 900;
    final child = _BookmarkPanel(
      conversationId: conversationId,
      onJump: (id) {
        Navigator.pop(context);
        onJump?.call(id);
      },
      onInsert: (b) {
        Navigator.pop(context);
        onInsert?.call(b);
      },
    );

    if (wide) {
      showDialog(
        context: context,
        useRootNavigator: true,
        builder: (_) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 460,
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: child,
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useRootNavigator: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        builder: (_) => ClipRRect(
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
          child: child,
        ),
      );
    }
  }
}

class _BookmarkPanel extends ConsumerWidget {
  final String conversationId;
  final void Function(String? messageId) onJump;
  final void Function(Bookmark) onInsert;

  const _BookmarkPanel({
    required this.conversationId,
    required this.onJump,
    required this.onInsert,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(bookmarksProvider(conversationId));

    return DefaultTabController(
      length: 2,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
            child: Row(
              children: [
                Icon(Icons.bookmarks, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                const Text('북마크',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 8),
          TabBar(
            labelColor: theme.colorScheme.primary,
            tabs: const [
              Tab(text: '장소'),
              Tab(text: '일정'),
            ],
          ),
          Flexible(
            child: async.when(
              data: (list) {
                final places = list.where((b) => b.isPlace).toList();
                final itins = list.where((b) => b.isItinerary).toList();
                return TabBarView(
                  children: [
                    _list(context, ref, places, '북마크한 장소가 없어요'),
                    _list(context, ref, itins, '북마크한 일정이 없어요'),
                  ],
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.all(30),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(30),
                child: Text('오류: $e'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(BuildContext context, WidgetRef ref, List<Bookmark> items,
      String emptyText) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Text(emptyText,
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _tile(context, ref, items[i]),
    );
  }

  Widget _tile(BuildContext context, WidgetRef ref, Bookmark b) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(b.isPlace ? Icons.place : Icons.map,
                  size: 15, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(b.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13.5)),
              ),
              if (b.fromSavedPlan)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('저장됨',
                      style: TextStyle(
                          fontSize: 9.5, color: Colors.amber.shade800)),
                ),
            ],
          ),
          if (b.isPlace && b.place?.address != null)
            Padding(
              padding: const EdgeInsets.only(top: 3, left: 21),
              child: Text(b.place!.address!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ),
          if (b.isItinerary && b.itinerary != null)
            Padding(
              padding: const EdgeInsets.only(top: 3, left: 21),
              child: Text(
                  '${b.itinerary!.destination} · ${b.itinerary!.duration}일',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => onInsert(b),
                icon: const Icon(Icons.push_pin_outlined, size: 14),
                label: const Text('대화에 표시', style: TextStyle(fontSize: 11.5)),
                style: _btnStyle,
              ),
              // ★ 장소 = info 팝업 / 일정 = 원본으로 (있을 때만)
              if (b.isPlace)
                TextButton.icon(
                  onPressed: () {
                    _showPlaceInfo(context, b);
                  },
                  icon: const Icon(Icons.info_outline, size: 14),
                  label: const Text('정보', style: TextStyle(fontSize: 11.5)),
                  style: _btnStyle,
                )
              else if (b.messageId != null)
                TextButton.icon(
                  onPressed: () => onJump(b.messageId),
                  icon: const Icon(Icons.my_location, size: 14),
                  label: const Text('원본으로', style: TextStyle(fontSize: 11.5)),
                  style: _btnStyle,
                ),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.delete_outline,
                    size: 18, color: Colors.grey.shade400),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                onPressed: () async {
                  await ref
                      .read(bookmarkActionsProvider)
                      .remove(conversationId, b.id);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }



static final _btnStyle = TextButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    minimumSize: const Size(0, 30),
  );

  void _showPlaceInfo(BuildContext context, Bookmark b) {
    final p = b.place;
    if (p == null) return;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.place, size: 18),
            const SizedBox(width: 6),
            Expanded(child: Text(p.name)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (p.placeType != null)
              _infoRow(Icons.category, p.placeType!),
            if (p.address != null) _infoRow(Icons.location_on, p.address!),
            if (b.note.isNotEmpty) _infoRow(Icons.sticky_note_2, b.note),
          ],
        ),
        actions: [
          if (p.name.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                final uri = Uri.parse(
                    'https://map.naver.com/p/search/${Uri.encodeComponent(p.name)}');
                launchUrl(uri, mode: LaunchMode.externalApplication);
              },
              icon: const Icon(Icons.map, size: 16),
              label: const Text('네이버 지도'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 15, color: Colors.grey.shade500),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );
}

class _BookmarkDropdown extends ConsumerWidget {
  final String conversationId;
  final void Function(Bookmark)? onInsert;
  final void Function(String?)? onJump;

  const _BookmarkDropdown({
    required this.conversationId,
    this.onInsert,
    this.onJump,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final list = ref.watch(bookmarksProvider(conversationId)).value ?? [];
    if (list.isEmpty) return const SizedBox.shrink();

    final places = list.where((b) => b.isPlace).toList();
    final itins = list.where((b) => b.isItinerary).toList();

    return PopupMenuButton<Bookmark>(
      tooltip: '북마크',
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(Icons.bookmarks_outlined,
              size: 19, color: theme.colorScheme.primary),
          Positioned(
            right: -4, top: -4,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                  color: Colors.redAccent, shape: BoxShape.circle),
              constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
              child: Text('${list.length}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 9)),
            ),
          ),
        ],
      ),
      onSelected: (b) => onInsert?.call(b),
      itemBuilder: (_) => [
        if (itins.isNotEmpty)
          const PopupMenuItem(
            enabled: false,
            height: 28,
            child: Text('일정',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ...itins.map((b) => PopupMenuItem(
              value: b,
              child: Row(
                children: [
                  const Icon(Icons.map, size: 15),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(b.label,
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
              ),
            )),
        if (places.isNotEmpty)
          const PopupMenuItem(
            enabled: false,
            height: 28,
            child: Text('장소',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ...places.map((b) => PopupMenuItem(
              value: b,
              child: Row(
                children: [
                  const Icon(Icons.place, size: 15),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(b.label,
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
              ),
            )),
      ],
    );
  }
}
