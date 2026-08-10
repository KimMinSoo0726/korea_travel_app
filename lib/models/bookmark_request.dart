import 'bookmark.dart';

class BookmarkRequest {
  final String type;
  final String label;
  final String? messageId;
  final BookmarkPlace? place;
  final BookmarkItinerary? itinerary;

  BookmarkRequest({
    required this.type,
    required this.label,
    this.messageId,
    this.place,
    this.itinerary,
  });
}