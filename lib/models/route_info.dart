class RouteInfo {
  final String mode;
  final List<List<double>> path;
  final int distance;        // m
  final int duration;        // ms
  final int fare;
  final int transferCount;
  final int totalWalkTime;   // sec
  final int totalWalkDistance;
  final List<RouteSegment> segments;   // 대중교통
  final List<RouteLeg> legs;           // 도보
  final bool transitUnavailable;
  final int fallbackWalk;
  final bool straight;
  final bool cached;

  RouteInfo({
    required this.mode,
    required this.path,
    this.distance = 0,
    this.duration = 0,
    this.fare = 0,
    this.transferCount = 0,
    this.totalWalkTime = 0,
    this.totalWalkDistance = 0,
    this.segments = const [],
    this.legs = const [],
    this.transitUnavailable = false,
    this.fallbackWalk = 0,
    this.straight = false,
    this.cached = false,
  });

  bool get hasDetail => segments.isNotEmpty || legs.isNotEmpty;

  String get durationLabel {
    final m = (duration / 60000).round();
    if (m < 60) return '$m분';
    return '${m ~/ 60}시간 ${m % 60}분';
  }

  String get distanceLabel =>
      distance < 1000 ? '${distance}m' : '${(distance / 1000).toStringAsFixed(1)}km';

  factory RouteInfo.fromMap(Map<String, dynamic> m) => RouteInfo(
        mode: m['mode'] ?? 'car',
        path: ((m['path'] ?? []) as List)
            .map<List<double>>((e) =>
                [(e[0] as num).toDouble(), (e[1] as num).toDouble()])
            .toList(),
        distance: (m['distance'] ?? 0).round(),
        duration: (m['duration'] ?? 0).round(),
        fare: (m['fare'] ?? 0) as int,
        transferCount: (m['transferCount'] ?? 0) as int,
        totalWalkTime: (m['totalWalkTime'] ?? 0) as int,
        totalWalkDistance: (m['totalWalkDistance'] ?? 0) as int,
        segments: ((m['segments'] ?? []) as List)
            .map((e) => RouteSegment.fromMap(
                (e as Map).map((k, v) => MapEntry('$k', v))))
            .toList(),
        legs: ((m['legs'] ?? []) as List)
            .map((e) =>
                RouteLeg.fromMap((e as Map).map((k, v) => MapEntry('$k', v))))
            .toList(),
        transitUnavailable: m['transitUnavailable'] == true,
        fallbackWalk: (m['fallbackWalk'] ?? 0) as int,
        straight: m['straight'] == true,
        cached: m['cached'] == true,
      );
}

/// 장소 → 장소 구간 (대중교통)
class RouteSegment {
  final String from;
  final String to;
  final bool fallbackWalk;
  final List<RouteLeg> legs;

  RouteSegment({
    required this.from,
    required this.to,
    this.fallbackWalk = false,
    this.legs = const [],
  });

  factory RouteSegment.fromMap(Map<String, dynamic> m) => RouteSegment(
        from: m['segmentFrom'] ?? '',
        to: m['segmentTo'] ?? '',
        fallbackWalk: m['fallbackWalk'] == true,
        legs: ((m['legs'] ?? []) as List)
            .map((e) =>
                RouteLeg.fromMap((e as Map).map((k, v) => MapEntry('$k', v))))
            .toList(),
      );
}

/// 이동 단위 (걷기 / 버스 / 지하철)
class RouteLeg {
  final String mode;        // WALK | BUS | SUBWAY | EXPRESSBUS | TRAIN
  final String? route;      // "지선:1128"
  final String? routeColor;
  final String? fromName;
  final String? toName;
  final int distance;
  final int sectionTime;    // sec
  final List<RouteStep> steps;
  final List<StationInfo> stations;

  RouteLeg({
    required this.mode,
    this.route,
    this.routeColor,
    this.fromName,
    this.toName,
    this.distance = 0,
    this.sectionTime = 0,
    this.steps = const [],
    this.stations = const [],
  });

  bool get isWalk => mode == 'WALK';

  String get modeLabel {
    switch (mode) {
      case 'WALK': return '도보';
      case 'BUS': return '버스';
      case 'SUBWAY': return '지하철';
      case 'EXPRESSBUS': return '고속버스';
      case 'TRAIN': return '기차';
      case 'AIRPLANE': return '항공';
      default: return mode;
    }
  }

  String get timeLabel {
    final m = (sectionTime / 60).round();
    return m < 1 ? '1분 미만' : '$m분';
  }

  /// "지선:1128" → "1128"
  String get routeName {
    if (route == null) return '';
    final i = route!.indexOf(':');
    return i >= 0 ? route!.substring(i + 1) : route!;
  }

  factory RouteLeg.fromMap(Map<String, dynamic> m) => RouteLeg(
        mode: m['mode'] ?? 'WALK',
        route: m['route'],
        routeColor: m['routeColor'],
        fromName: m['fromName'],
        toName: m['toName'],
        distance: (m['distance'] ?? 0).round(),
        sectionTime: (m['sectionTime'] ?? 0) as int,
        steps: ((m['steps'] ?? []) as List)
            .map((e) =>
                RouteStep.fromMap((e as Map).map((k, v) => MapEntry('$k', v))))
            .toList(),
        stations: ((m['stations'] ?? []) as List)
            .map((e) => StationInfo.fromMap(
                (e as Map).map((k, v) => MapEntry('$k', v))))
            .toList(),
      );
}

class RouteStep {
  final String description;
  final String? streetName;
  final int distance;

  RouteStep({required this.description, this.streetName, this.distance = 0});

  factory RouteStep.fromMap(Map<String, dynamic> m) => RouteStep(
        description: m['description'] ?? '',
        streetName: m['streetName'],
        distance: (m['distance'] ?? 0).round(),
      );
}

class StationInfo {
  final String name;
  final double? lat;
  final double? lng;

  StationInfo({required this.name, this.lat, this.lng});

  factory StationInfo.fromMap(Map<String, dynamic> m) => StationInfo(
        name: m['name'] ?? '',
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
      );
}