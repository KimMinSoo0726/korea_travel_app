/// 여행 취향 (사용자 기본값)
class TravelPreferences {
  final String pace;
  final List<String> interests;
  final String planningMode;

  const TravelPreferences({
    this.pace = 'normal',
    this.interests = const [],
    this.planningMode = 'auto',
  });

  static const paceOptions = {
    'packed': '빡빡하게',
    'normal': '보통',
    'relaxed': '릴렉스',
  };

  static const interestOptions = [
    '미식', '문화재','미술관','박물관','시장', '카페', '풍경', '액티비티', '쇼핑', '야경',
  ];

  static const planningOptions = {
    'planned': '계획적',
    'auto': '무계획 (알아서 짜주세요)',
  };

  String get paceLabel => paceOptions[pace] ?? '보통';
  String get planningLabel => planningOptions[planningMode] ?? '무계획';

  TravelPreferences copyWith({
    String? pace,
    List<String>? interests,
    String? planningMode,
  }) =>
      TravelPreferences(
        pace: pace ?? this.pace,
        interests: interests ?? this.interests,
        planningMode: planningMode ?? this.planningMode,
      );

  factory TravelPreferences.fromMap(Map<String, dynamic> m) =>
      TravelPreferences(
        pace: m['pace'] ?? 'normal',
        interests: ((m['interests'] ?? []) as List).map((e) => '$e').toList(),
        planningMode: m['planningMode'] ?? 'auto',
      );

  Map<String, dynamic> toMap() => {
        'pace': pace,
        'interests': interests,
        'planningMode': planningMode,
      };
}

/// 이번 여행의 조건
class TripContext {
  final String origin;
  final String destination;
  final String startDate;
  final int duration;
  final String arrivalTime;
  final String returnLocation;
  final String returnDeadline;
  final int adults;
  final int children;
  final String transport;
  final String budget;

  const TripContext({
    this.origin = '',
    this.destination = '',
    this.startDate = '',
    this.duration = 0,
    this.arrivalTime = '',
    this.returnLocation = '',
    this.returnDeadline = '',
    this.adults = 0,
    this.children = 0,
    this.transport = '',
    this.budget = '',
  });

static const transportOptions = ['자동차', '대중교통', '도보'];

  int get people => adults + children;

  bool get isEmpty =>
      origin.isEmpty && destination.isEmpty && startDate.isEmpty;

  TripContext copyWith({
    String? origin,
    String? destination,
    String? startDate,
    int? duration,
    String? arrivalTime,
    String? returnLocation,
    String? returnDeadline,
    int? adults,
    int? children,
    String? transport,
    String? budget,
  }) =>
      TripContext(
        origin: origin ?? this.origin,
        destination: destination ?? this.destination,
        startDate: startDate ?? this.startDate,
        duration: duration ?? this.duration,
        arrivalTime: arrivalTime ?? this.arrivalTime,
        returnLocation: returnLocation ?? this.returnLocation,
        returnDeadline: returnDeadline ?? this.returnDeadline,
        adults: adults ?? this.adults,
        children: children ?? this.children,
        transport: transport ?? this.transport,
        budget: budget ?? this.budget,
      );

  factory TripContext.fromMap(Map<String, dynamic> m) => TripContext(
        origin: m['origin'] ?? '',
        destination: m['destination'] ?? '',
        startDate: m['startDate'] ?? '',
        duration: m['duration'] is int
            ? m['duration']
            : int.tryParse('${m['duration']}') ?? 0,
        arrivalTime: m['arrivalTime'] ?? '',
        returnLocation: m['returnLocation'] ?? '',
        returnDeadline: m['returnDeadline'] ?? '',
        adults: m['adults'] is int ? m['adults'] : 0,
        children: m['children'] is int ? m['children'] : 0,
        transport: m['transport'] ?? '',
        budget: m['budget'] ?? '',
      );

  Map<String, dynamic> toMap() => {
        'origin': origin,
        'destination': destination,
        'startDate': startDate,
        'duration': duration,
        'arrivalTime': arrivalTime,
        'returnLocation': returnLocation,
        'returnDeadline': returnDeadline,
        'adults': adults,
        'children': children,
        'transport': transport,
        'budget': budget,
      };
}

/// 통합 설정
class TripSettings {
  final TravelPreferences prefs;
  final TripContext trip;

  const TripSettings({
    this.prefs = const TravelPreferences(),
    this.trip = const TripContext(),
  });

  TripSettings copyWith({TravelPreferences? prefs, TripContext? trip}) =>
      TripSettings(prefs: prefs ?? this.prefs, trip: trip ?? this.trip);

  factory TripSettings.fromMap(Map<String, dynamic> m) => TripSettings(
        prefs: TravelPreferences.fromMap(
            ((m['prefs'] ?? {}) as Map).map((k, v) => MapEntry('$k', v))),
        trip: TripContext.fromMap(
            ((m['trip'] ?? {}) as Map).map((k, v) => MapEntry('$k', v))),
      );

  Map<String, dynamic> toMap() => {
        'prefs': prefs.toMap(),
        'trip': trip.toMap(),
      };

    String transportToMode(String t) {
      if (t.contains('대중교통')) return 'transit';
      if (t.contains('도보')) return 'walk';
      return 'car';
    }


  /// LLM에게 보낼 요청문
  String toPromptMessage() {
    final b = StringBuffer('아래 조건으로 여행 일정을 다시 추천해주세요.\n\n');

    if (trip.destination.isNotEmpty) b.writeln('- 목적지: ${trip.destination}');
    if (trip.origin.isNotEmpty) b.writeln('- 출발지: ${trip.origin}');
    if (trip.startDate.isNotEmpty) {
      b.writeln('- 출발일: ${trip.startDate}'
          '${trip.duration > 0 ? " (${trip.duration}일)" : ""}');
    }
    if (trip.arrivalTime.isNotEmpty) {
      b.writeln('- 목적지 도착 시각: ${trip.arrivalTime}');
    }
    if (trip.returnLocation.isNotEmpty) {
      b.writeln('- 복귀: ${trip.returnLocation}'
          '${trip.returnDeadline.isNotEmpty ? " (${trip.returnDeadline}까지 도착)" : ""}');
    }
    if (trip.people > 0) {
      b.writeln('- 인원: 총 ${trip.people}명 '
          '(성인 ${trip.adults}, 아동 ${trip.children})');
    }
    if (trip.transport.isNotEmpty) b.writeln('- 교통편: ${trip.transport}');
    if (trip.budget.isNotEmpty) b.writeln('- 예산: ${trip.budget}');

    b.writeln('- 여행 강도: ${prefs.paceLabel}');
    if (prefs.interests.isNotEmpty) {
      b.writeln('- 관심사: ${prefs.interests.join(", ")}');
    }
    b.writeln('- 계획 방식: ${prefs.planningLabel}');

    if (prefs.planningMode == 'planned') {
      b.writeln('\n각 단계마다 제 의견을 물어보며 함께 만들어주세요.');
    } else {
      b.writeln('\n제 취향에 맞게 알아서 완성된 코스를 제안해주세요.');
    }
    return b.toString();
  }
}