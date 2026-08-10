import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/travel_plan.dart';
import 'api_provider.dart';
import 'auth_provider.dart';
import '../models/plan_group.dart';
import 'bookmark_provider.dart';


final planGroupsProvider = FutureProvider<List<PlanGroup>>((ref) async {
  final uid = ref.watch(uidProvider);
  if (uid == null) return [];
  return ref.watch(apiServiceProvider).listPlanGroups();
});


final plansProvider = FutureProvider<List<TravelPlan>>((ref) async {
  final uid = ref.watch(uidProvider);
  if (uid == null) return [];
  return ref.watch(apiServiceProvider).listPlans();
});

final singlePlanProvider =
    FutureProvider.family<TravelPlan?, String>((ref, planId) async {
  final uid = ref.watch(uidProvider);
  if (uid == null) return null;
  return ref.watch(apiServiceProvider).getPlan(planId);
});

final planActionsProvider = Provider((ref) => PlanActions(ref));

class PlanActions {
  final Ref ref;
  PlanActions(this.ref);

  Future<String?> save(TravelPlan plan,
      {String? conversationId, String? messageId}) async {
    final saved = await ref.read(apiServiceProvider).savePlan(
          plan,
          conversationId: conversationId,
          messageId: messageId,
        );
    ref.invalidate(planGroupsProvider);
    return saved?.id;
  }

  Future<void> delete(String planId, {String? conversationId}) async {
    await ref.read(apiServiceProvider).deletePlan(planId);
    ref.invalidate(planGroupsProvider);
    if (conversationId != null) {
      ref.invalidate(bookmarksProvider(conversationId));   
    }
  }

  Future<void> update(TravelPlan plan) async {
    await ref.read(apiServiceProvider).updatePlan(plan);
    ref.invalidate(planGroupsProvider);
    ref.invalidate(singlePlanProvider(plan.id));
  }
}