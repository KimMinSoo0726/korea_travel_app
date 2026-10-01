import 'package:flutter/material.dart';

import '../../services/api_service.dart';

import 'naver_map_stub.dart'
    if (dart.library.js_interop) 'naver_map_web.dart';

import '../../models/travel_plan.dart';
import '../../models/route_info.dart';
import 'route_detail_sheet.dart';

List<int?> computeMapIndices(PlanDay day) {
  final out = <int?>[];
  int n = 0;
  for (final it in day.items) {
    if (it.lat != null && it.lng != null) {
      out.add(n);
      n++;
    } else {
      out.add(null);
    }
  }
  return out;
}

String transportToMode(String? transport) {
  final t = transport ?? '';
  if (t.contains('대중교통') || t.contains('기차') || t.contains('버스')) return 'transit';
  if (t.contains('도보') || t.contains('걷')) return 'walk';
  if (t.contains('자전거')) return 'bike';
  return 'car';
}

class DayMapController {
  String? _id;
  void attach(String id) => _id = id;
  bool get isReady => _id != null;

  void focus(int i) { if (_id != null) focusMarker(_id!, i); }
  void reset() { if (_id != null) resetView(_id!); }
  void drawRoute(List<List<double>> p) { if (_id != null) drawRoute_(_id!, p); }
  void refresh(List<PlanItem> p) { if (_id != null) refreshMarkers(_id!, p); }
}

class DayMapView extends StatefulWidget {
  final PlanDay day;
  final double height;
  final DayMapController? controller;
  final String mode;

  const DayMapView({
    super.key,
    required this.day,
    this.height = 260,
    this.controller,
    this.mode = 'car',
  });

  @override
  State<DayMapView> createState() => _DayMapViewState();
}

class _DayMapViewState extends State<DayMapView> {
  bool _routeRequested = false;
  bool _routeLoading = false;
  RouteInfo? _route;

  @override
  void didUpdateWidget(DayMapView old) {
    super.didUpdateWidget(old);

    final oldKey = _pointKey(old.day);
    final newKey = _pointKey(widget.day);

    // 좌표 시퀀스나 모드가 바뀌면 재조회
    if (oldKey != newKey || old.mode != widget.mode) {
      final points = _points;
      widget.controller?.refresh(points);
      _routeRequested = false;
      setState(() => _route = null);
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _loadRoute(points);
      });
    }
  }

  List<PlanItem> get _points =>
      widget.day.items.where((e) => e.lat != null && e.lng != null).toList();

  String _pointKey(PlanDay day) => day.items
      .where((e) => e.lat != null && e.lng != null)
      .map((e) => '${e.lat!.toStringAsFixed(5)},${e.lng!.toStringAsFixed(5)}')
      .join('|');

 Future<void> _loadRoute(List<PlanItem> points) async {
    if (_routeRequested || points.length < 2) return;
    _routeRequested = true;
    setState(() => _routeLoading = true);

    try {
      final data = await ApiService().getRoute(
        points
            .map((p) => {
                  'lat': p.lat,
                  'lng': p.lng,
                  'name': p.placeName ?? p.activity,   // ★ 안내용 이름
                })
            .toList(),
        widget.mode,
      );

      final info = RouteInfo.fromMap(data);
      debugPrint(
          '🛣 mode=${widget.mode} 좌표 ${info.path.length}개 캐시=${info.cached}');

      if (!mounted) return;
      setState(() => _route = info);
      if (info.path.isNotEmpty) widget.controller?.drawRoute(info.path);
    } catch (e) {
      debugPrint('경로 조회 실패: $e');
    } finally {
      if (mounted) setState(() => _routeLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final points = _points;

    if (points.isEmpty) {
      return Container(
        height: widget.height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text('표시할 좌표가 없습니다',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,          // ★ 이게 있어야 함
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: double.infinity,
            height: widget.height,
            child: buildNaverMap(points, (id) {
              widget.controller?.attach(id);
              Future.delayed(const Duration(milliseconds: 600), () {
                if (mounted) _loadRoute(points);
              });
            }),
          ),
        ),

        // ── 경로 요약 바 ──
        if (_routeLoading)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.8)),
                const SizedBox(width: 8),
                Text('경로를 계산하는 중...',
                    style:
                        TextStyle(fontSize: 11.5, color: Colors.grey.shade500)),
              ],
            ),
          )
        else if (_route != null && _route!.path.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: InkWell(
              onTap: _route!.hasDetail
                  ? () => showRouteDetail(context, _route!)
                  : null,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(_modeIcon, size: 15, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        [
                          _route!.durationLabel,
                          _route!.distanceLabel,
                          if (_route!.fare > 0) '${_route!.fare}원',
                          if (_route!.transferCount > 0)
                            '환승 ${_route!.transferCount}회',
                        ].join('  ·  '),
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary),
                      ),
                    ),
                    if (_route!.hasDetail) ...[
                      Text('길 안내',
                          style: TextStyle(
                              fontSize: 11.5,
                              color: theme.colorScheme.primary)),
                      Icon(Icons.chevron_right,
                          size: 15, color: theme.colorScheme.primary),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  IconData get _modeIcon {
    switch (widget.mode) {
      case 'walk': return Icons.directions_walk;
      case 'bike': return Icons.directions_bike;
      case 'transit': return Icons.directions_transit;
      default: return Icons.directions_car;
    }
  }
}