import 'travel_plan.dart';

class PlanGroup {
  final String? conversationId;
  final String conversationTitle;
  final DateTime conversationCreatedAt;
  final List<TravelPlan> plans;

  PlanGroup({
    required this.conversationId,
    required this.conversationTitle,
    required this.conversationCreatedAt,
    required this.plans,
  });

  factory PlanGroup.fromMap(Map<String, dynamic> m) => PlanGroup(
        conversationId: m['conversationId'],
        conversationTitle: m['conversationTitle'] ?? '대화 없음',
        conversationCreatedAt:
            DateTime.tryParse(m['conversationCreatedAt'] ?? '') ??
                DateTime.now(),
        plans: ((m['plans'] ?? []) as List)
            .map((e) => TravelPlan.fromMap(
                (e as Map).map((k, v) => MapEntry(k.toString(), v))))
            .toList(),
      );
}

/// "2026년 7월 23일 (목)"
String formatDateKo(DateTime d) {
  const days = ['월', '화', '수', '목', '금', '토', '일'];
  return '${d.year}년 ${d.month}월 ${d.day}일 (${days[d.weekday - 1]})';
}

/// "오후 3:24"
String formatTimeKo(DateTime d) {
  final isPm = d.hour >= 12;
  var h = d.hour % 12;
  if (h == 0) h = 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '${isPm ? "오후" : "오전"} $h:$m';
}