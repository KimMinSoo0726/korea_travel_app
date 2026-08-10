import 'package:flutter/material.dart';

import '../../models/route_info.dart';
Future<void> showRouteDetail(BuildContext context, RouteInfo route) {
  final w = MediaQuery.of(context).size.width;

  // 넓은 화면 → 다이얼로그
  if (w >= 900) {
    return showDialog(
      context: context,
      useRootNavigator: true,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 520,
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: RouteDetailSheet(route: route, asDialog: true),
        ),
      ),
    );
  }

  // 좁은 화면 → 바텀시트
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.85,
    ),
    builder: (_) => RouteDetailSheet(route: route),
  );
}

class RouteDetailSheet extends StatelessWidget {
  final RouteInfo route;
  final bool asDialog;

  const RouteDetailSheet({
    super.key,
    required this.route,
    this.asDialog = false,
  });

  @override
  Widget build(BuildContext context) {
    if (asDialog) {
      return Container(
        color: Colors.white,
        child: _content(context, null),
      );
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 1.0,
      expand: false,
      builder: (_, sc) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: _content(context, sc),
      ),
    );
  }

  Widget _content(BuildContext context, ScrollController? sc) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 핸들 (시트일 때만)
        if (!asDialog)
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

        // 요약
        Padding(
          padding: EdgeInsets.fromLTRB(20, asDialog ? 18 : 6, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_modeIcon, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_modeLabel,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    _stat('⏱', route.durationLabel),
                    _stat('📏', route.distanceLabel),
                    if (route.fare > 0) _stat('💳', _won(route.fare)),
                    if (route.transferCount > 0)
                      _stat('🔄', '환승 ${route.transferCount}회'),
                    if (route.totalWalkDistance > 0)
                      _stat('🚶', '도보 ${route.totalWalkDistance}m'),
                  ],
                ),
              ),
              if (route.transitUnavailable)
                _notice(theme, '대중교통 경로를 가져올 수 없어 도보 경로로 안내합니다.',
                    Colors.orange),
              if (!route.transitUnavailable && route.fallbackWalk > 0)
                _notice(theme,
                    '일부 구간(${route.fallbackWalk}곳)은 대중교통이 없어 도보로 안내합니다.',
                    Colors.orange),
              if (route.straight)
                _notice(theme, '실제 경로를 찾지 못해 직선으로 표시했습니다.', Colors.grey),
            ],
          ),
        ),
        const Divider(height: 1),

        // 상세
        Flexible(
          child: ListView(
            controller: sc,
            shrinkWrap: asDialog,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
            children: [
              if (route.segments.isNotEmpty)
                ...route.segments.map((s) => _segmentBlock(theme, s))
              else if (route.legs.isNotEmpty)
                ...route.legs.map((l) => _legTile(theme, l))
              else
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(30),
                    child: Text('상세 안내가 없습니다',
                        style: TextStyle(color: Colors.grey.shade500)),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ... _segmentBlock, _legTile, _stat, _notice 등 나머지는 그대로

  // ───────── 구간(장소→장소) ─────────

  Widget _segmentBlock(ThemeData theme, RouteSegment seg) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.07),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text('${seg.from}  →  ${seg.to}',
                    maxLines: 2,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary)),
              ),
              if (seg.fallbackWalk)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('도보 대체',
                      style: TextStyle(
                          fontSize: 10, color: Colors.orange.shade700)),
                ),
            ],
          ),
        ),
        ...seg.legs.map((l) => _legTile(theme, l)),
        const SizedBox(height: 14),
      ],
    );
  }

  // ───────── 이동 단위 ─────────

  Widget _legTile(ThemeData theme, RouteLeg leg) {
    final color = _legColor(leg);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 타임라인
          Column(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(_legIcon(leg), size: 15, color: Colors.white),
              ),
              Container(width: 2, height: 26, color: Colors.grey.shade200),
            ],
          ),
          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (!leg.isWalk && leg.routeName.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(leg.routeName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold)),
                      ),
                    Text(leg.modeLabel,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Text(
                      [
                        leg.timeLabel,
                        if (leg.distance > 0)
                          leg.distance < 1000
                              ? '${leg.distance}m'
                              : '${(leg.distance / 1000).toStringAsFixed(1)}km',
                      ].join(' · '),
                      style:
                          TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
                    ),
                  ],
                ),

                // 승하차 정류장
                if (!leg.isWalk && leg.fromName != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('🚏 승차  ${leg.fromName}',
                            style: const TextStyle(fontSize: 12.5)),
                        if (leg.toName != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text('🏁 하차  ${leg.toName}',
                                style: const TextStyle(fontSize: 12.5)),
                          ),
                        if (leg.stations.length > 2)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: _stationsExpander(leg),
                          ),
                      ],
                    ),
                  ),

                // 도보 턴바이턴
                if (leg.isWalk && leg.steps.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _walkSteps(leg),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stationsExpander(RouteLeg leg) => Theme(
        data: ThemeData(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(left: 4, bottom: 4),
          title: Text('정류장 ${leg.stations.length}개 보기',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          children: leg.stations
              .asMap()
              .entries
              .map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          child: Text('${e.key + 1}',
                              style: TextStyle(
                                  fontSize: 10, color: Colors.grey.shade400)),
                        ),
                        Expanded(
                          child: Text(e.value.name,
                              style: TextStyle(
                                  fontSize: 11.5, color: Colors.grey.shade700)),
                        ),
                      ],
                    ),
                  ))
              .toList(),
        ),
      );

  Widget _walkSteps(RouteLeg leg) => Theme(
        data: ThemeData(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(left: 4, bottom: 4),
          title: Text('상세 안내 ${leg.steps.length}단계',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          children: leg.steps
              .map((s) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 3, right: 6),
                          child: Icon(Icons.circle,
                              size: 5, color: Colors.grey.shade300),
                        ),
                        Expanded(
                          child: Text(s.description,
                              style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.grey.shade700,
                                  height: 1.35)),
                        ),
                      ],
                    ),
                  ))
              .toList(),
        ),
      );

  // ───────── 헬퍼 ─────────

  Widget _stat(String emoji, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          Text(text,
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w500)),
        ],
      );

  Widget _notice(ThemeData theme, String text, MaterialColor color) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: color.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 13, color: color.shade700),
              const SizedBox(width: 6),
              Expanded(
                child: Text(text,
                    style: TextStyle(fontSize: 11.5, color: color.shade800)),
              ),
            ],
          ),
        ),
      );

  IconData get _modeIcon {
    switch (route.mode) {
      case 'walk': return Icons.directions_walk;
      case 'bike': return Icons.directions_bike;
      case 'transit': return Icons.directions_transit;
      default: return Icons.directions_car;
    }
  }

  String get _modeLabel {
    switch (route.mode) {
      case 'walk': return '도보 경로';
      case 'bike': return '자전거 경로 (도보 기준)';
      case 'transit': return '대중교통 경로';
      default: return '자동차 경로';
    }
  }

  IconData _legIcon(RouteLeg leg) {
    switch (leg.mode) {
      case 'WALK': return Icons.directions_walk;
      case 'BUS': return Icons.directions_bus;
      case 'SUBWAY': return Icons.subway;
      case 'TRAIN': return Icons.train;
      case 'EXPRESSBUS': return Icons.airport_shuttle;
      case 'AIRPLANE': return Icons.flight;
      default: return Icons.circle;
    }
  }

  Color _legColor(RouteLeg leg) {
    if (leg.routeColor != null && leg.routeColor!.isNotEmpty) {
      final v = int.tryParse(leg.routeColor!, radix: 16);
      if (v != null) return Color(0xFF000000 | v);
    }
    switch (leg.mode) {
      case 'WALK': return Colors.grey.shade400;
      case 'BUS': return const Color(0xFF33A02C);
      case 'SUBWAY': return const Color(0xFF1F78B4);
      case 'TRAIN': return const Color(0xFF6A3D9A);
      default: return const Color(0xFF2E7D6B);
    }
  }

  static String _won(int v) {
    final s = v.toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '${b.toString()}원';
  }
}