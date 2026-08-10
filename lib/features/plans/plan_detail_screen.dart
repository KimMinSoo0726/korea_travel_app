import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/travel_plan.dart';
import '../../providers/plan_provider.dart';
import '../map/naver_map_view.dart';
import '../chat/widgets/place_detail_dialog.dart';

class PlanDetailScreen extends ConsumerWidget {
  final String planId;
  final VoidCallback onBack;

  const PlanDetailScreen({
    super.key,
    required this.planId,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(singlePlanProvider(planId));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 16, 4),
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack),
              const SizedBox(width: 4),
              Text('플랜 상세',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        Expanded(
          child: planAsync.when(
            data: (plan) => plan == null
                ? const Center(child: Text('플랜을 찾을 수 없습니다.'))
                : _PlanDetailBody(plan: plan),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('오류: $e')),
          ),
        ),
      ],
    );
  }
}

class _PlanDetailBody extends StatelessWidget {
  final TravelPlan plan;
  const _PlanDetailBody({required this.plan});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = plan.summary;

    // 전체 합계
    final allItems =
        plan.itinerary.expand((d) => d.items).toList(growable: false);
    final totalMin = allItems.fold<int>(0, (a, e) => a + e.durationMin);
    final totalCost = allItems.fold<int>(0, (a, e) => a + e.avgPrice);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (plan.planLabel.isNotEmpty)
              _badge(theme, plan.planLabel, filled: true),
            _badge(theme, '🔥 ${plan.styleLabel}'),
            if (plan.transport.isNotEmpty) _badge(theme, '🚌 ${plan.transport}'),
          ],
        ),
        const SizedBox(height: 12),
        Text(plan.title,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),

        // 요약 카드
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _row('테마', plan.theme),
                _row('스타일', plan.styleLabel),
                _row('교통편', plan.transport),
                _row('목적지', s.destination),
                _row('출발지', s.origin),
                _row('도착 시각', s.arrivalTime),
                _row(
                    '복귀',
                    s.returnLocation.isEmpty
                        ? ''
                        : '${s.returnLocation}'
                            '${s.returnDeadline.isNotEmpty ? " (${s.returnDeadline}까지)" : ""}'),
                _row(
                    '날짜',
                    s.startDate.isEmpty
                        ? ''
                        : '${s.startDate}  (${s.duration}일)'),
                _row(
                    '인원',
                    s.people == 0
                        ? ''
                        : '${s.people}명 (성인 ${s.adults} · 아동 ${s.children})'),
                _row('예산', s.budget),
                if (s.estimatedCost > 0)
                  _row('예상 비용', wonFormat(s.estimatedCost)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // 일정 헤더 + 전체 합계
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('📅 일정',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const Spacer(),
            Text(
              [
                '총 ${allItems.length}개',
                if (totalMin > 0) _durationText(totalMin),
                if (totalCost > 0) '1인 ${wonFormat(totalCost)}',
              ].join('  ·  '),
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...plan.itinerary.map((day) => _DayCard(day: day,
              mode: transportToMode(plan.transport),)),

        if (plan.accommodations.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('🏨 추천 숙소',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...plan.accommodations.map((acc) => _AccommodationCard(acc: acc)),
        ],
      ],
    );
  }

  Widget _badge(ThemeData theme, String text, {bool filled = false}) {
    return Container(
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
  }

  Widget _row(String label, String value) {
    if (value.isEmpty || value == 'null') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(label,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}

/// "3시간 30분"
String _durationText(int totalMin) {
  final h = totalMin ~/ 60;
  final m = totalMin % 60;
  if (h > 0 && m > 0) return '$h시간 $m분';
  if (h > 0) return '$h시간';
  return '$m분';
}

class _DayCard extends StatefulWidget {
   final PlanDay day;
  final String mode;                          // ★
  const _DayCard({required this.day, this.mode = 'car'});

  @override
  State<_DayCard> createState() => _DayCardState();
}

class _DayCardState extends State<_DayCard> {
  final _ctrl = DayMapController();

  @override
  Widget build(BuildContext context) {
    final day = widget.day;
    final wd = weekdayKo(day.date);
    final weekend = isWeekend(day.date);
    final mapIdx = computeMapIndices(day);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 일차 헤더
            Row(
              children: [
                Text('${day.day}일차  ·  ${day.date}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Color(0xFF2E7D6B))),
                if (wd.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color:
                          weekend ? Colors.red.shade50 : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(weekend ? '$wd · 주말' : wd,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: weekend
                                ? Colors.red.shade400
                                : Colors.grey.shade600)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),

             DayMapView(day: day, height: 240, controller: _ctrl,
                mode: widget.mode, ),
            
            const Divider(height: 24),

            // 일정 항목
            for (int i = 0; i < day.items.length; i++)
              _detailItemTile(context, day.items[i], mapIdx[i], _ctrl),

            // 하루 합계
            const Divider(height: 20),
            _daySummary(day),
          ],
        ),
      ),
    );
  }

  Widget _daySummary(PlanDay day) {
    final totalMin = day.items.fold<int>(0, (a, e) => a + e.durationMin);
    final totalCost = day.items.fold<int>(0, (a, e) => a + e.avgPrice);
    final mapped = day.items.where((e) => e.lat != null).length;

    return Row(
      children: [
        Icon(Icons.summarize_outlined, size: 14, color: Colors.grey.shade400),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            [
              '${day.items.length}개 일정',
              if (mapped > 0) '지도 $mapped곳',
              if (totalMin > 0) '총 ${_durationText(totalMin)}',
              if (totalCost > 0) '1인 약 ${wonFormat(totalCost)}',
            ].join('  ·  '),
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
          ),
        ),
        TextButton.icon(
          onPressed: () => _ctrl.reset(),
          icon: const Icon(Icons.map_outlined, size: 14),
          label: const Text('지도 전체보기', style: TextStyle(fontSize: 11)),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 28),
          ),
        ),
      ],
    );
  }

  Widget _detailItemTile(BuildContext context, PlanItem item, int? markerIndex,
      DayMapController ctrl) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 마커 번호 — 탭하면 지도 이동
          SizedBox(
            width: 30,
            child: markerIndex == null
                ? const SizedBox()
                : Tooltip(
                    message: '지도에서 보기',
                    child: InkWell(
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
          ),
          // 본문 — 탭하면 상세 팝업
          Expanded(
            child: InkWell(
              onTap:
                  item.hasDetail ? () => showPlaceDetail(context, item) : null,
              borderRadius: BorderRadius.circular(8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 50,
                    child: Text(item.time,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: Color(0xFF2E7D6B))),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(item.activity,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500)),
                            ),
                            if (item.hasDetail)
                              Icon(Icons.info_outline,
                                  size: 14, color: Colors.grey.shade400),
                          ],
                        ),
                        if (item.placeName != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '${item.placeName}'
                              '${item.placeType != null ? " · ${item.placeType}" : ""}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12.5, color: Colors.grey.shade700),
                            ),
                          ),
                        if (item.address != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Text(item.address!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey.shade400)),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 2,
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
                              if (item.closedDay != null)
                                Text('🚫 ${item.closedDay}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.orange.shade700)),
                              if (item.verified)
                                Text('✅ 확인됨',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.green.shade600))
                              else if (item.placeName != null)
                                Text('⚠️ 추정',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.orange.shade600)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child:
                Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade300),
          ),
        ],
      ),
    );
  }
}

class _AccommodationCard extends StatelessWidget {
  final Accommodation acc;
  const _AccommodationCard({required this.acc});

  Future<void> _openUrl(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('링크를 열 수 없습니다.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(acc.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                if (acc.rating != null)
                  Text('⭐ ${acc.rating}',
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  if (acc.type != null)
                    Text(acc.type!,
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade700)),
                  if (acc.type != null &&
                      (acc.priceRange != null || acc.estimatedPrice > 0))
                    Text('  ·  ',
                        style: TextStyle(color: Colors.grey.shade400)),
                  if (acc.priceRange != null || acc.estimatedPrice > 0)
                    Text(
                      acc.priceRange ?? '1박 ${wonFormat(acc.estimatedPrice)}',
                      style: TextStyle(
                          fontSize: 14,
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold),
                    ),
                ],
              ),
            ),
            if (acc.address != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(acc.address!,
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade400)),
              ),
            if (acc.note != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(acc.note!,
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic)),
              ),
            if (acc.bookingLinks.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: acc.bookingLinks
                    .map((link) => OutlinedButton.icon(
                          onPressed: () => _openUrl(context, link.url),
                          icon: const Icon(Icons.open_in_new, size: 14),
                          label: Text(link.platform,
                              style: const TextStyle(fontSize: 12)),
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}