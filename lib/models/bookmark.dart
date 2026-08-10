class Bookmark {
  final String id;
  final String conversationId;
  final String type;            // place | itinerary
  final String? messageId;
  final String label;
  final String note;
  final BookmarkPlace? place;
  final BookmarkItinerary? itinerary;
  final bool fromSavedPlan;
  final String? planId;
  final DateTime createdAt;

  Bookmark({
    required this.id,
    required this.conversationId,
    required this.type,
    this.messageId,
    required this.label,
    this.note = '',
    this.place,
    this.itinerary,
    this.fromSavedPlan = false,
    this.planId,
    required this.createdAt,
  });

  bool get isPlace => type == 'place';
  bool get isItinerary => type == 'itinerary';

  factory Bookmark.fromMap(Map<String, dynamic> m) => Bookmark(
        id: m['_id'] ?? '',
        conversationId: m['conversationId'] ?? '',
        type: m['type'] ?? 'place',
        messageId: m['messageId'],
        label: m['label'] ?? '',
        note: m['note'] ?? '',
        place: m['place'] == null
            ? null
            : BookmarkPlace.fromMap(
                (m['place'] as Map).map((k, v) => MapEntry('$k', v))),
        itinerary: m['itinerary'] == null
            ? null
            : BookmarkItinerary.fromMap(
                (m['itinerary'] as Map).map((k, v) => MapEntry('$k', v))),
        fromSavedPlan: m['fromSavedPlan'] == true,
        planId: m['planId'],
        createdAt: DateTime.tryParse(m['createdAt'] ?? '') ?? DateTime.now(),
      );
}

class BookmarkPlace {
  final String name;
  final String? placeType;
  final String? address;
  final double? lat;
  final double? lng;
  final String? placeId;

  BookmarkPlace({
    required this.name,
    this.placeType,
    this.address,
    this.lat,
    this.lng,
    this.placeId,
  });

  factory BookmarkPlace.fromMap(Map<String, dynamic> m) => BookmarkPlace(
        name: m['name'] ?? '',
        placeType: m['placeType'],
        address: m['address'],
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
        placeId: m['placeId'],
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'placeType': placeType,
        'address': address,
        'lat': lat,
        'lng': lng,
        'placeId': placeId,
      };
}

class BookmarkItinerary {
  final String planLabel;
  final String title;
  final int dayCount;
  final String destination;
  final int duration;

  BookmarkItinerary({
    required this.planLabel,
    required this.title,
    this.dayCount = 0,
    this.destination = '',
    this.duration = 0,
  });

  factory BookmarkItinerary.fromMap(Map<String, dynamic> m) =>
      BookmarkItinerary(
        planLabel: m['planLabel'] ?? '',
        title: m['title'] ?? '',
        dayCount: (m['dayCount'] ?? 0) as int,
        destination: m['destination'] ?? '',
        duration: (m['duration'] ?? 0) as int,
      );

  Map<String, dynamic> toMap() => {
        'planLabel': planLabel,
        'title': title,
        'dayCount': dayCount,
        'destination': destination,
        'duration': duration,
      };
}