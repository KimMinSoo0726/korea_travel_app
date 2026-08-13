import 'package:cloud_functions/cloud_functions.dart';

import '../core/constants/app_constants.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/travel_plan.dart';
import '../models/plan_group.dart';
import '../models/trip_settings.dart';
import '../models/bookmark.dart';

/// callable 응답을 안전하게 Map으로
Map<String, dynamic> asMap(dynamic v) {
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
  return {};
}

List<Map<String, dynamic>> asMapList(dynamic v) {
  if (v is List) return v.map(asMap).toList();
  return [];
}

class ApiService {
  final _functions =
      FirebaseFunctions.instanceFor(region: AppConstants.functionsRegion);

  Future<Map<String, dynamic>> _call(
      String name, [Map<String, dynamic>? params]) async {
    final callable = _functions.httpsCallable(name);
    final res = await callable.call(params ?? {});
    return asMap(res.data);
  }

  // ───────── 대화 ─────────

  Future<List<Conversation>> listConversations() async {
    final data = await _call('listConversations');
    return asMapList(data['conversations']).map(Conversation.fromMap).toList();
  }

  Future<void> deleteConversation(String conversationId) async {
    await _call('deleteConversation', {'conversationId': conversationId});
  }

  // ───────── 메시지 ─────────

  Future<List<Message>> listMessages(String conversationId) async {
    final data =
        await _call('listMessages', {'conversationId': conversationId});
    return asMapList(data['messages']).map(Message.fromMap).toList();
  }

  Future<ChatResult> chat({
    String? conversationId,
    required String message,
  }) async {
    final data = await _call('chatWithGemini', {
      'conversationId': conversationId,
      'message': message,
    });
    return ChatResult(
      conversationId: data['conversationId'] ?? '',
      userMessage: Message.fromMap(asMap(data['userMessage'])),
      aiMessage: Message.fromMap(asMap(data['aiMessage'])),
      needsEnrich: data['needsEnrich'] == true,
    );
  }

  Future<EnrichResult> enrichPlanMessage(String messageId) async {
    final data = await _call('enrichPlanMessage', {'messageId': messageId});
    return EnrichResult(
      planJson: data['planJson'] == null
          ? null
          : (data['planJson'] as Map).map((k, v) => MapEntry('$k', v)),
      matched: (data['matched'] ?? 0) as int,
      total: (data['total'] ?? 0) as int,
    );
  }

  // ───────── 플랜 ─────────

  Future<List<TravelPlan>> listPlans() async {
    final data = await _call('listPlans');
    return asMapList(data['plans']).map(TravelPlan.fromMap).toList();
  }

  Future<List<PlanGroup>> listPlanGroups() async {
    final data = await _call('listPlanGroups');
    return asMapList(data['groups']).map(PlanGroup.fromMap).toList();
  }

  Future<TravelPlan?> getPlan(String planId) async {
    final data = await _call('getPlan', {'planId': planId});
    final p = asMap(data['plan']);
    if (p.isEmpty) return null;
    return TravelPlan.fromMap(p);
  }

  Future<TravelPlan?> savePlan(TravelPlan plan,
      {String? conversationId, String? messageId}) async {
    final data = await _call('savePlan', {
      'plan': plan.toJson(),
      'conversationId': conversationId,
      'messageId': messageId,               
    });
    final p = asMap(data['plan']);
    if (p.isEmpty) return null;
    return TravelPlan.fromMap(p);
  }

  Future<void> updatePlan(TravelPlan plan) async {
    final json = plan.toJson()..['_id'] = plan.id;
    await _call('updatePlan', {'plan': json});
  }

  Future<void> deletePlan(String planId) async {
    await _call('deletePlan', {'planId': planId});
  }

  // ───────── 설정 ─────────

  Future<TravelPreferences> getUserPrefs() async {
    final data = await _call('getUserSettings');
    return TravelPreferences.fromMap(asMap(data['prefs']));
  }

  Future<void> saveUserPrefs(TravelPreferences prefs) async {
    await _call('saveUserSettings', {'prefs': prefs.toMap()});
  }

  Future<TripSettings> getConversationSettings(String? conversationId) async {
    final data = await _call('getConversationSettings', {
      'conversationId': conversationId,
    });
    return TripSettings.fromMap(asMap(data['settings']));
  }

  Future<void> saveConversationSettings(
      String conversationId, TripSettings settings) async {
    await _call('saveConversationSettings', {
      'conversationId': conversationId,
      'settings': settings.toMap(),
    });
  }


  //--qwen
 Future<QwenResult> chatQwen({
    String? conversationId,
    required String message,
  }) async {
    final callable = _functions.httpsCallable(
      'chatWithQwen',
      options: HttpsCallableOptions(
        timeout: const Duration(minutes: 5),   // ★ 기본 70초 → 5분
      ),
    );
    final res = await callable.call({
      'conversationId': conversationId,
      'message': message,
    });
    final data = asMap(res.data);
    return QwenResult(
      text: data['text'] ?? '',
      planJson: data['planJson'] == null
          ? null
          : (data['planJson'] as Map).map((k, v) => MapEntry('$k', v)),
    );
  }

  Future<QwenResult> chatDeepseek({
    String? conversationId,
    required String message,
  }) async {
    final callable = _functions.httpsCallable(
      'chatWithDeepSeek',
      options: HttpsCallableOptions(timeout: const Duration(minutes: 5)),
    );
    final res = await callable.call({
      'conversationId': conversationId,
      'message': message,
    });
    final data = asMap(res.data);
    return QwenResult(
      text: data['text'] ?? '',
      planJson: data['planJson'] == null
          ? null
          : (data['planJson'] as Map).map((k, v) => MapEntry('$k', v)),
    );
  }


// ───────── 북마크 ─────────

  Future<List<Bookmark>> listBookmarks(String conversationId) async {
    final data =
        await _call('listBookmarks', {'conversationId': conversationId});
    return asMapList(data['bookmarks']).map(Bookmark.fromMap).toList();
  }

  Future<Bookmark?> addBookmark({
    required String conversationId,
    required String type,
    required String label,
    String? messageId,
    String? note,
    BookmarkPlace? place,
    BookmarkItinerary? itinerary,
    String? planId,
    bool fromSavedPlan = false,
  }) async {
    final data = await _call('addBookmark', {
      'conversationId': conversationId,
      'type': type,
      'label': label,
      'messageId': messageId,
      'note': note,
      'place': place?.toMap(),
      'itinerary': itinerary?.toMap(),
      'planId': planId,
      'fromSavedPlan': fromSavedPlan,
    });
    final b = asMap(data['bookmark']);
    if (b.isEmpty) return null;
    return Bookmark.fromMap(b);
  }

  Future<void> deleteBookmark(String bookmarkId) async {
    await _call('deleteBookmark', {'bookmarkId': bookmarkId});
  }

  Future<void> updateBookmarkNote(String bookmarkId, String note) async {
    await _call('updateBookmark', {'bookmarkId': bookmarkId, 'note': note});
  }
}

// ───────── 응답 타입 ─────────

class ChatResult {
  final String conversationId;
  final Message userMessage;
  final Message aiMessage;
  final bool needsEnrich;

  ChatResult({
    required this.conversationId,
    required this.userMessage,
    required this.aiMessage,
    this.needsEnrich = false,
  });
}

class EnrichResult {
  final Map<String, dynamic>? planJson;
  final int matched;
  final int total;

  EnrichResult({this.planJson, this.matched = 0, this.total = 0});
}



  class QwenResult {
  final String text;
  final Map<String, dynamic>? planJson;
  QwenResult({required this.text, this.planJson});
}

