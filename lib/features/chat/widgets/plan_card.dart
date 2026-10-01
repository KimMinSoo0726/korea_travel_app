import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/travel_plan.dart';
import '../../../providers/plan_provider.dart';
import 'place_detail_dialog.dart';
import '../../map/naver_map_view.dart';
import '../../../models/bookmark.dart';
import '../../../models/bookmark_request.dart';
import '../../../providers/bookmark_provider.dart';

class PlanCard extends ConsumerStatefulWidget {
  final TravelPlan plan;
  final String? conversationId;
  final bool isEnriching;
  final void Function(String replanText) onReplan;
  final String? messageId;
  final void Function(BookmarkRequest req)? onBookmark;

  const PlanCard({
    super.key,
    required this.plan,
    required this.conversationId,
    this.isEnriching = false,
    this.messageId,
    required this.onReplan,
    this.onBookmark,
  });

  @override
  ConsumerState<PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends ConsumerState<PlanCard> {
  late List<PlanDay> _itinerary;
 final Map<int, DayMapController> _mapControllers = {};
  DayMapController _controllerFor(int dayIndex) =>
      _mapControllers.putIfAbsent(dayIndex, () => DayMapController());

  @override
  void initState() {
    super.initState();
    // 삭제 편집을 위해 로컬 복사본 사용
    _itinerary = widget.plan.itinerary;
  }

   @override
  void didUpdateWidget(PlanCard old) {
    super.didUpdateWidget(old);
    if (old.plan != widget.plan) {
      setState(() => _itinerary = widget.plan.itinerary);
    }
  }

  /// 지도 동기화 (삭제·순서변경 공통)
  void _syncMap(int dayIndex) {
    final ctrl = _mapControllers[dayIndex];
    if (ctrl == null || !ctrl.isReady) return;
    final points = _itinerary[dayIndex]
        .items
        .where((e) => e.lat != null && e.lng != null)
        .toList();
    ctrl.refresh(points);
  }

  void _deleteItem(int dayIndex, int itemIndex) {
    setState(() {
      final day = _itinerary[dayIndex];
      final items = [...day.items]..removeAt(itemIndex);
      _itinerary = [..._itinerary];
      _itinerary[dayIndex] = day.copyWith(items: items);
    });
    _syncMap(dayIndex);
  }

  void _reorderItem(int dayIndex, int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final day = _itinerary[dayIndex];
      final items = [...day.items];
      items.insert(newIndex, items.removeAt(oldIndex));
      _itinerary = [..._itinerary];
      _itinerary[dayIndex] = day.copyWith(items: items);
    });
    _syncMap(dayIndex);
  }

  void _recalcDayTimes(int dayIndex) {
    setState(() {
      final day = _itinerary[dayIndex];
      _itinerary = [..._itinerary];
      _itinerary[dayIndex] = day.copyWith(items: recalcTimes(day.items));
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('시간을 다시 계산했어요.')),
    );
  }

/// 일정이 비어 있으면 "선택용 요약 카드"
  bool get _isPreview =>
      _itinerary.isEmpty || _itinerary.every((d) => d.items.isEmpty);

  String get _selectMessage {
    final label = widget.plan.planLabel.isNotEmpty
        ? widget.plan.planLabel
        : widget.plan.title;
    return '$label 로 정할게요. 이 코스 기준으로 날짜별 상세 일정을 짜주세요.';
  }

  TravelPlan get _editedPlan =>
      widget.plan.copyWith(itinerary: _itinerary);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = widget.plan;
    final s = plan.summary;

    final card = Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 헤더 ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: theme.colorScheme.primary.withOpacity(0.06),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (plan.planLabel.isNotEmpty)
                      _badge(theme, plan.planLabel, filled: true),
                    _badge(theme, '🔥 ${plan.styleLabel}'),
                    if (plan.transport.isNotEmpty)
                      _badge(theme, '🚌 ${plan.transport}'),
                  ],
                ),
                const SizedBox(height: 10),
                Text(plan.title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                _summaryLine(s),
                const SizedBox(height: 4),
                _timeLine(s),
              ],
            ),
          ),

          // ── 요약 모드: 선택 안내만 ──
          if (_isPreview)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  Icon(Icons.touch_app_outlined,
                      size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('이 코스로 상세 일정 만들기',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary)),
                  ),
                  Icon(Icons.arrow_forward_ios,
                      size: 13, color: theme.colorScheme.primary),
                ],
              ),
            )

          // ── 상세 모드: 기존 UI ──
          else ...[
            ExpansionTile(
              title: const Text('📅 일정 보기 (탭하면 상세 · ☰ 끌어 순서 변경)',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              tilePadding: const EdgeInsets.symmetric(horizontal: 16),
              childrenPadding:
                  const EdgeInsets.only(left: 16, right: 16, bottom: 8),
              children: [
                for (int d = 0; d < _itinerary.length; d++)
                  _dayBlock(_itinerary[d], d),
              ],
            ),
            const Divider(height: 1),
            if (plan.accommodations.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text('🏨 추천 숙소',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ),
              ...plan.accommodations
                  .map((acc) => _accommodationTile(context, acc)),
            ],
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _savePlan,
                      icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                      label: const Text('이 플랜 저장'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => widget.onBookmark?.call(
                      BookmarkRequest(
                        type: 'itinerary',
                        label: widget.plan.title,
                        messageId: widget.messageId,
                        itinerary: BookmarkItinerary(
                          planLabel: widget.plan.planLabel,
                          title: widget.plan.title,
                          dayCount: widget.plan.itinerary.length,
                          destination: widget.plan.summary.destination,
                          duration: widget.plan.summary.duration,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.bookmark_border, size: 18),
                    label: const Text('일정 북마크'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: _isPreview
          ? InkWell(
              onTap: () => widget.onReplan(_selectMessage),
              borderRadius: BorderRadius.circular(16),
              child: card,
            )
          : card,
    );
  }



  Widget _badge(ThemeData theme, String text, {bool filled = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: filled
              ? theme.colorScheme.primary
              : theme.colorScheme.primary.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(
                color: filled ? Colors.white : theme.colorScheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      );

  Widget _summaryLine(PlanSummary s) {
    final parts = <String>[
      if (s.destination.isNotEmpty) '📍${s.destination}',
      if (s.duration > 0) '${s.duration}일',
      if (s.people > 0) '${s.people}명',
      if (s.estimatedCost > 0) '약 ${wonFormat(s.estimatedCost)}',
    ];
    return Text(parts.join('  ·  '),
        style: TextStyle(color: Colors.grey.shade700, fontSize: 13));
  }

  Widget _timeLine(PlanSummary s) {
    final parts = <String>[
      if (s.origin.isNotEmpty) '출발 ${s.origin}',
      if (s.arrivalTime.isNotEmpty) '도착 ${s.arrivalTime}',
      if (s.returnLocation.isNotEmpty)
        '복귀 ${s.returnLocation}'
            '${s.returnDeadline.isNotEmpty ? " ${s.returnDeadline}까지" : ""}',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(parts.join('  →  '),
        style: TextStyle(color: Colors.grey.shade500, fontSize: 12));
  }
 Widget _dayBlock(PlanDay day, int dayIndex) {
    final wd = weekdayKo(day.date);
    final weekend = isWeekend(day.date);
    final mapIdx = computeMapIndices(day);
    final ctrl = _controllerFor(dayIndex);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Row(
            children: [
              Text('${day.day}일차  ${day.date}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13)),
              if (wd.isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: weekend ? Colors.red.shade50 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(wd,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: weekend
                              ? Colors.red.shade400
                              : Colors.grey.shade600)),
                ),
              ],
              const Spacer(),
              TextButton.icon(
                onPressed: () => _recalcDayTimes(dayIndex),
                icon: const Icon(Icons.update, size: 14),
                label: const Text('시간 재계산',
                    style: TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 28),
                ),
              ),
            ],
          ),
        ),
        ExpansionTile(
          title: Text(
            widget.isEnriching ? '🗺 지도 (위치 확인 중...)' : '🗺 지도 보기',
            style: const TextStyle(fontSize: 12),
          ),
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          children: [
               DayMapView(day: day, height: 240, controller: ctrl,
              
                mode: transportToMode(widget.plan.transport),
              
            ),
          ],
        ),


        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: Text('☰ 를 끌어 순서를 바꿀 수 있어요',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
        ),

        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: day.items.length,
          onReorder: (o, n) => _reorderItem(dayIndex, o, n),
          proxyDecorator: (child, index, animation) => Material(
            elevation: 4,
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            child: child,
          ),
          itemBuilder: (ctx, i) => Container(
            key: ValueKey('d$dayIndex-${day.items[i].reorderKey}-$i'),
            child: _itemTile(day.items[i], dayIndex, i, mapIdx[i], ctrl),
          ),
        ),
      ],
    );
  }
Widget _itemTile(PlanItem item, int dayIndex, int itemIndex,
      int? markerIndex, DayMapController ctrl) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 드래그 핸들 ──
          ReorderableDragStartListener(
            index: itemIndex,
            child: Padding(
              padding: const EdgeInsets.only(top: 3, right: 2),
              child: Icon(Icons.drag_indicator,
                  size: 18, color: Colors.grey.shade300),
            ),
          ),

          // ── 마커 번호 (탭 → 지도 이동) ──
          SizedBox(
            width: 30,
            child: markerIndex == null
                ? (widget.isEnriching
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: Center(
                          child: SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: Colors.grey.shade300),
                          ),
                        ),
                      )
                    : const SizedBox())
                : InkWell(
                    onTap: () => ctrl.focus(markerIndex),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2E7D6B),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: Text('${markerIndex + 1}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
          ),

          // ── 본문 (탭 → 상세 팝업) ──
         Expanded(
            child: InkWell(
              onTap:
                  item.hasDetail ? () => showPlaceDetail(context, item) : null,
              onLongPress: item.placeName == null
                  ? null
                  : () => widget.onBookmark?.call(
                        BookmarkRequest(
                          type: 'place',
                          label: item.placeName!,
                          messageId: widget.messageId,
                          place: BookmarkPlace(
                            name: item.placeName!,
                            placeType: item.placeType,
                            address: item.address,
                            lat: item.lat,
                            lng: item.lng,
                          ),
                        ),
                      ),
              borderRadius: BorderRadius.circular(8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 46,
                    child: Text(item.time,
                        style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF2E7D6B),
                            fontWeight: FontWeight.w600)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 활동명
                        Text(item.activity,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500)),

                        // 장소명 · 분류
                        if (item.placeName != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '${item.placeName}'
                              '${item.placeType != null ? " · ${item.placeType}" : ""}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade700),
                            ),
                          ),

                        // 주소
                        if (item.address != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Text(item.address!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey.shade400)),
                          ),

                        // 시간 · 가격 · 영업 · 휴무 · 검증
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 2,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (item.durationLabel.isNotEmpty)
                                Text('⏱ ${item.durationLabel}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade500)),
                              if (item.avgPrice > 0)
                                Text('💰 1인 ${wonFormat(item.avgPrice)}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade500)),
                              if (item.businessHours != null)
                                Text('🕐 ${item.businessHours}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade500)),
                              if (item.useFee != null)
                                Text('🎟 ${item.useFee}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade500)),
                              if (item.menu != null)
                                Text('🍽 ${item.menu}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade500)),
                              if (item.closedDay != null)
                                Text('🚫 ${item.closedDay}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.red.shade400)),
                              
                              if (item.verifyStatus == 'confirmed')
                                Text('✅ 확인됨',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.green.shade600))
                              else if (item.placeName != null &&
                                  !widget.isEnriching)
                                Text('⚠️ 추정됨',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.orange.shade600)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (item.hasDetail)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, left: 4),
                      child: Icon(Icons.info_outline,
                          size: 14, color: Colors.grey.shade400),
                    ),
                ],
              ),
            ),
          ),

          // ── 삭제 ──
          SizedBox(
            width: 28,
            height: 28,
            child: IconButton(
              icon: Icon(Icons.close, size: 16, color: Colors.grey.shade400),
              padding: EdgeInsets.zero,
              splashRadius: 16,
              onPressed: () => _confirmDeleteItem(item, dayIndex, itemIndex),
            ),
          ),
        ],
      ),
    );
  }


        
  Future<void> _confirmDeleteItem(
      PlanItem item, int dayIndex, int itemIndex) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('일정 삭제'),
        content: Text("'${item.placeName ?? item.activity}'를 일정에서 뺄까요?"),
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
    if (ok == true) _deleteItem(dayIndex, itemIndex);
  }

  Widget _accommodationTile(BuildContext context, Accommodation acc) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(acc.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                ),
                if (acc.rating != null)
                  Text('⭐ ${acc.rating}',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  if (acc.type != null)
                    Text(acc.type!,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600)),
                  if (acc.type != null &&
                      (acc.priceRange != null || acc.estimatedPrice > 0))
                    Text('  ·  ',
                        style: TextStyle(color: Colors.grey.shade400)),
                  if (acc.priceRange != null || acc.estimatedPrice > 0)
                    Text(
                      acc.priceRange ?? '1박 ${wonFormat(acc.estimatedPrice)}',
                      style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ...acc.bookingLinks.map((link) => OutlinedButton.icon(
                      onPressed: () => _openUrl(link.url),
                      icon: const Icon(Icons.open_in_new, size: 14),
                      label: Text(link.platform,
                          style: const TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 0),
                        minimumSize: const Size(0, 32),
                      ),
                    )),
                FilledButton.tonalIcon(
                  onPressed: () => widget.onReplan(
                      '${acc.name}(으)로 정할게요. 이 숙소를 기준으로 일정을 다시 추천해주세요.'),
                  icon: const Icon(Icons.refresh, size: 14),
                  label: const Text('이 숙소로 다시 추천',
                      style: TextStyle(fontSize: 12)),
                  style: FilledButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    minimumSize: const Size(0, 32),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('링크를 열 수 없습니다.')));
      }
    }
  }

 Future<void> _savePlan() async {
    final id = await ref.read(planActionsProvider).save(
          _editedPlan,
          conversationId: widget.conversationId,
          messageId: widget.messageId,  
        );

    if (id != null && widget.conversationId != null) {
      ref.invalidate(bookmarksProvider(widget.conversationId!));   
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(content: Text(id != null ? '플랜을 저장하고 북마크에 추가했어요.' : '저장에 실패했어요.')),
      );
    }
  }
}