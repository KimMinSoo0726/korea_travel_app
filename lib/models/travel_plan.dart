// ============================================================
// 여러 플랜 후보 래퍼
// ============================================================
class PlanOptions {
  final String message;
  final List<TravelPlan> plans;

  PlanOptions({required this.message, required this.plans});

  factory PlanOptions.fromJson(Map<String, dynamic> j) => PlanOptions(
        message: j['message'] ?? '',
        plans: ((j['plans'] ?? []) as List)
            .map((e) => TravelPlan.fromJson('', e.cast<String, dynamic>()))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'type': 'plan_options',
        'message': message,
        'plans': plans.map((e) => e.toJson()).toList(),
      };

  static bool isPlanOptions(Map<String, dynamic>? json) =>
      json != null && json['type'] == 'plan_options';
}

// ============================================================
// 단일 여행 플랜
// ============================================================
class TravelPlan {
  final String id;
  final String planLabel;
  final String title;
  final String theme;
  final String style;      // packed / normal / relaxed
  final String transport;  // 교통편
  final PlanSummary summary;
  final List<PlanDay> itinerary;
  final List<Accommodation> accommodations;
  final DateTime savedAt;
  final String? conversationId;

  TravelPlan({
    required this.id,
    required this.planLabel,
    required this.title,
    required this.theme,
    required this.style,
    required this.transport,
    required this.summary,
    required this.itinerary,
    required this.accommodations,
    required this.savedAt,
    this.conversationId,
  });

  factory TravelPlan.fromJson(String id, Map<String, dynamic> j) => TravelPlan(
        id: id,
        planLabel: j['planLabel'] ?? '',
        title: j['title'] ?? '제목 없음',
        theme: j['theme'] ?? '일반',
        style: j['style'] ?? 'normal',
        transport: j['transport'] ?? '',
        summary:
            PlanSummary.fromJson((j['summary'] ?? {}).cast<String, dynamic>()),
        itinerary: ((j['itinerary'] ?? []) as List)
            .map((e) => PlanDay.fromJson(e.cast<String, dynamic>()))
            .toList(),
        accommodations: ((j['accommodations'] ?? []) as List)
            .map((e) => Accommodation.fromJson(e.cast<String, dynamic>()))
            .toList(),
        conversationId: j['conversationId'], 
        savedAt: DateTime.tryParse(j['savedAt'] ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'planLabel': planLabel,
        'title': title,
        'theme': theme,
        'style': style,
        'transport': transport,
        'summary': summary.toJson(),
        'itinerary': itinerary.map((e) => e.toJson()).toList(),
        'accommodations': accommodations.map((e) => e.toJson()).toList(),
        'conversationId': conversationId,
        'savedAt': savedAt.toIso8601String(),
      };

      /// MongoDB 문서용 (_id 포함)
  factory TravelPlan.fromMap(Map<String, dynamic> j) =>
      TravelPlan.fromJson(j['_id'] ?? '', j);


  /// 스타일 한글 라벨
  String get styleLabel {
    switch (style) {
      case 'packed':
        return '빡세게';
      case 'relaxed':
        return '널널하게';
      default:
        return '보통';
    }
  }

  // TravelPlan 안에
TravelPlan copyWith({
  String? id,
  List<PlanDay>? itinerary,
  DateTime? savedAt,
}) =>
    TravelPlan(
      id: id ?? this.id,
      planLabel: planLabel,
      title: title,
      theme: theme,
      style: style,
      transport: transport,
      summary: summary,
      itinerary: itinerary ?? this.itinerary,
      accommodations: accommodations,
      savedAt: savedAt ?? this.savedAt,
    );
}

// ============================================================
// 여행 요약
// ============================================================
class PlanSummary {
  final String destination;
  final String origin;
  final String arrivalTime;      // 목적지 도착 시각
  final String returnLocation;   // 복귀 장소
  final String returnDeadline;   // 복귀 도착 시한
  final String startDate;
  final int duration;
  final int people;
  final int adults;
  final int children;
  final String budget;
  final int estimatedCost;

  PlanSummary({
    required this.destination,
    required this.origin,
    required this.arrivalTime,
    required this.returnLocation,
    required this.returnDeadline,
    required this.startDate,
    required this.duration,
    required this.people,
    required this.adults,
    required this.children,
    required this.budget,
    required this.estimatedCost,
  });

  factory PlanSummary.fromJson(Map<String, dynamic> j) => PlanSummary(
        destination: j['destination'] ?? '',
        origin: j['origin'] ?? '',
        arrivalTime: j['arrivalTime'] ?? '',
        returnLocation: j['returnLocation'] ?? '',
        returnDeadline: j['returnDeadline'] ?? '',
        startDate: j['startDate'] ?? '',
        duration: _toInt(j['duration']),
        people: _toInt(j['people']),
        adults: _toInt(j['adults']),
        children: _toInt(j['children']),
        budget: j['budget'] ?? '미지정',
        estimatedCost: _toInt(j['estimatedCost']),
      );

  Map<String, dynamic> toJson() => {
        'destination': destination,
        'origin': origin,
        'arrivalTime': arrivalTime,
        'returnLocation': returnLocation,
        'returnDeadline': returnDeadline,
        'startDate': startDate,
        'duration': duration,
        'people': people,
        'adults': adults,
        'children': children,
        'budget': budget,
        'estimatedCost': estimatedCost,
      };
}

// ============================================================
// 하루 일정
// ============================================================
class PlanDay {
  final int day;
  final String date;
  final List<PlanItem> items;

  PlanDay({required this.day, required this.date, required this.items});

  factory PlanDay.fromJson(Map<String, dynamic> j) => PlanDay(
        day: _toInt(j['day']),
        date: j['date'] ?? '',
        items: ((j['items'] ?? []) as List)
            .map((e) => PlanItem.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'day': day,
        'date': date,
        'items': items.map((e) => e.toJson()).toList(),
      };

  // PlanDay 안에
  PlanDay copyWith({List<PlanItem>? items}) =>
    PlanDay(day: day, date: date, items: items ?? this.items);
}

// ============================================================
// 일정 항목
// ============================================================
class PlanItem {
  final String time;
  final String activity;
  final String? placeName;
  final String? placeType;
  final String? category;
  final String? address;
  final double? lat;
  final double? lng;
  final String? homepage;
  final String? businessHours;
  final String? closedDay;
  final String? phone;
  final String? searchUrl;
  final String? photoSearchUrl;
  final String? description;
  final int durationMin;
  final int avgPrice;
  final bool verified;
  final String? thumbnail;
  final List<String> images;
  final String? parking;
  final String? useFee;
  final String? menu;
  final String? reservation;
  final String? checkIn;
  final String? checkOut;
  final String? petAllowed;
  final String? creditCard;
  final String? tourContentId;

   PlanItem({
    required this.time,
    required this.activity,
    this.placeName,
    this.placeType,
    this.category,
    this.address,
    this.lat,
    this.lng,
    this.homepage,
    this.businessHours,
    this.closedDay,
    this.phone,
    this.searchUrl,
    this.photoSearchUrl,
    this.description,
    this.durationMin = 0,
    this.avgPrice = 0,
    this.verified = false,
    this.thumbnail,
    this.images = const [],
    this.parking,
    this.useFee,
    this.menu,
    this.reservation,
    this.checkIn,
    this.checkOut,
    this.petAllowed,
    this.creditCard,
    this.tourContentId,
  });

    factory PlanItem.fromJson(Map<String, dynamic> j) => PlanItem(
        time: j['time'] ?? '',
        activity: j['activity'] ?? '',
        placeName: j['placeName'],
        placeType: j['placeType'],
        category: j['category'],
        address: j['address'],
        lat: _toDoubleOrNull(j['lat']),
        lng: _toDoubleOrNull(j['lng']),
        homepage: j['homepage'],
        businessHours: j['businessHours'],
        closedDay: j['closedDay'],
        phone: j['phone'],
        searchUrl: j['searchUrl'],
        photoSearchUrl: j['photoSearchUrl'],
        description: j['description'],
        durationMin: _toInt(j['durationMin']),
        avgPrice: _toInt(j['avgPrice']),
        verified: j['verified'] == true,
        thumbnail: j['thumbnail'],
        images: ((j['images'] ?? []) as List).map((e) => '$e').toList(),
        parking: j['parking'],
        useFee: j['useFee'],
        menu: j['menu'],
        reservation: j['reservation'],
        checkIn: j['checkIn'],
        checkOut: j['checkOut'],
        petAllowed: j['petAllowed'],
        creditCard: j['creditCard'],
        tourContentId: j['tourContentId'],
      );

  Map<String, dynamic> toJson() => {
        'time': time,
        'activity': activity,
        'placeName': placeName,
        'placeType': placeType,
        'category': category,
        'address': address,
        'lat': lat,
        'lng': lng,
        'homepage': homepage,
        'businessHours': businessHours,
        'closedDay': closedDay,
        'phone': phone,
        'searchUrl': searchUrl,
        'photoSearchUrl': photoSearchUrl,
        'description': description,
        'durationMin': durationMin,
        'avgPrice': avgPrice,
        'verified': verified,
        'thumbnail': thumbnail,
        'images': images,
        'parking': parking,
        'useFee': useFee,
        'menu': menu,
        'reservation': reservation,
        'checkIn': checkIn,
        'checkOut': checkOut,
        'petAllowed': petAllowed,
        'creditCard': creditCard,
        'tourContentId': tourContentId,
      };
  /// 팝업에 띄울 만한 상세 정보가 있는지
  bool get hasDetail => placeName != null;

  String get durationLabel {
    if (durationMin <= 0) return '';
    final h = durationMin ~/ 60;
    final m = durationMin % 60;
    if (h > 0 && m > 0) return '$h시간 $m분';
    if (h > 0) return '$h시간';
    return '$m분';
  }

  /// 리스트 재정렬용 안정 키
  String get reorderKey => '$time|$activity|${placeName ?? ""}';

  PlanItem copyWith({String? time}) => PlanItem(
        time: time ?? this.time,
        activity: activity,
        placeName: placeName,
        placeType: placeType,
        category: category,
        address: address,
        lat: lat,
        lng: lng,
        homepage: homepage,
        businessHours: businessHours,
        closedDay: closedDay,
        phone: phone,
        searchUrl: searchUrl,
        photoSearchUrl: photoSearchUrl,
        description: description,
        durationMin: durationMin,
        avgPrice: avgPrice,
        verified: verified,
      );
}

// ============================================================
// 숙소
// ============================================================
class Accommodation {
  final String name;
  final String? type;
  final String? address;
  final double? lat;
  final double? lng;
  final String? priceRange;
  final int estimatedPrice;
  final String? rating;
  final List<BookingLink> bookingLinks;
  final String? note;
  final bool verified;

  Accommodation({
    required this.name,
    this.type,
    this.address,
    this.lat,
    this.lng,
    this.priceRange,
    this.estimatedPrice = 0,
    this.rating,
    this.bookingLinks = const [],
    this.note,
    this.verified = false,  
  });

  factory Accommodation.fromJson(Map<String, dynamic> j) => Accommodation(
        name: j['name'] ?? '',
        type: j['type'],
        address: j['address'],
        lat: _toDoubleOrNull(j['lat']),
        lng: _toDoubleOrNull(j['lng']),
        priceRange: j['priceRange'],
        estimatedPrice: _toInt(j['estimatedPrice']),
        rating: j['rating'],
        bookingLinks: ((j['bookingLinks'] ?? []) as List)
            .map((e) => BookingLink.fromJson(e.cast<String, dynamic>()))
            .toList(),
        note: j['note'],
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'address': address,
        'lat': lat,
        'lng': lng,
        'priceRange': priceRange,
        'estimatedPrice': estimatedPrice,
        'rating': rating,
        'bookingLinks': bookingLinks.map((e) => e.toJson()).toList(),
        'note': note,
        'verified': verified,
      };
}

// ============================================================
// 예약/검색 링크
// ============================================================
class BookingLink {
  final String platform;
  final String url;

  BookingLink({required this.platform, required this.url});

  factory BookingLink.fromJson(Map<String, dynamic> j) => BookingLink(
        platform: j['platform'] ?? '링크',
        url: j['url'] ?? '',
      );

  Map<String, dynamic> toJson() => {'platform': platform, 'url': url};
}

/// 순서 변경 후 시간 자동 재계산
List<PlanItem> recalcTimes(List<PlanItem> items, {int bufferMin = 30}) {
  if (items.isEmpty) return items;

  int? parse(String t) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(t.trim());
    if (m == null) return null;
    return int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
  }

  String fmt(int mins) {
    final m = mins % (24 * 60);
    return '${(m ~/ 60).toString().padLeft(2, '0')}:'
        '${(m % 60).toString().padLeft(2, '0')}';
  }

  var cur = parse(items.first.time) ?? 9 * 60;
  return items.map((it) {
    final result = it.copyWith(time: fmt(cur));
    cur += (it.durationMin > 0 ? it.durationMin : 60) + bufferMin;
    return result;
  }).toList();
}

// ============================================================
// 헬퍼
// ============================================================
int _toInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is double) return v.toInt();
  return int.tryParse('$v') ?? 0;
}

double? _toDoubleOrNull(dynamic v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  return double.tryParse('$v');
}

/// 금액 콤마 포맷 (예: 130000 -> "130,000원")
String wonFormat(int v) {
  final s = v.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return '${buf.toString()}원';
}

/// "2026-07-25" -> "토" (요일), 파싱 실패 시 빈 문자열
String weekdayKo(String dateStr) {
  final d = DateTime.tryParse(dateStr);
  if (d == null) return '';
  const days = ['월', '화', '수', '목', '금', '토', '일'];
  return days[d.weekday - 1]; // DateTime.weekday: 월=1 ... 일=7
}

/// 주말 여부 (토·일)
bool isWeekend(String dateStr) {
  final d = DateTime.tryParse(dateStr);
  if (d == null) return false;
  return d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;
}