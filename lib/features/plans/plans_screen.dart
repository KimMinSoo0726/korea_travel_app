import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/plan_group.dart';
import '../../models/travel_plan.dart';
import '../../providers/plan_provider.dart';

class PlansScreen extends ConsumerWidget {
  final void Function(String planId) onOpenPlan;
  const PlansScreen({super.key, required this.onOpenPlan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(planGroupsProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Row(
            children: [
              Text('저장된 플랜',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: () => ref.invalidate(planGroupsProvider),
              ),
            ],
          ),
        ),
        Expanded(
          child: groupsAsync.when(
            data: (groups) {
              if (groups.isEmpty) return const _EmptyPlans();
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(planGroupsProvider),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: groups.length,
                  itemBuilder: (_, i) => _GroupTile(
                    group: groups[i],
                    onOpenPlan: onOpenPlan,
                    onDelete: (p) => _confirmDelete(context, ref, p),
                  ),
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('오류: $e')),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, TravelPlan plan) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('플랜 삭제'),
        content: Text("'${plan.title}' 플랜을 삭제할까요?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('삭제')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(planActionsProvider).delete(
        plan.id,
        conversationId: plan.conversationId,);
    }
  }
}

/// 대분류 — 대화 시작 날짜
class _GroupTile extends StatelessWidget {
  final PlanGroup group;
  final void Function(String planId) onOpenPlan;
  final void Function(TravelPlan plan) onDelete;

  const _GroupTile({
    required this.group,
    required this.onOpenPlan,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Theme(
        // ExpansionTile 기본 구분선 제거
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
            child: Icon(Icons.forum_outlined,
                size: 20, color: theme.colorScheme.primary),
          ),
          title: Text(
            formatDateKo(group.conversationCreatedAt),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '${group.conversationTitle}  ·  플랜 ${group.plans.length}개',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
          children: group.plans
              .map((p) => _PlanSubTile(
                    plan: p,
                    onTap: () => onOpenPlan(p.id),
                    onDelete: () => onDelete(p),
                  ))
              .toList(),
        ),
      ),
    );
  }
}

/// 소분류 — 저장 시각
class _PlanSubTile extends StatelessWidget {
  final TravelPlan plan;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _PlanSubTile({
    required this.plan,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = plan.summary;

    final meta = [
      if (plan.theme.isNotEmpty) plan.theme,
      if (s.destination.isNotEmpty) s.destination,
      if (s.duration > 0) '${s.duration}일',
      if (s.people > 0) '${s.people}명',
    ].join('  ·  ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 8, 8),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 40,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.schedule,
                          size: 12, color: Colors.grey.shade400),
                      const SizedBox(width: 4),
                      Text(formatTimeKo(plan.savedAt),
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500)),
                      if (plan.planLabel.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(plan.planLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.primary)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(plan.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  if (meta.isNotEmpty)
                    Text(meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              color: Colors.grey.shade400,
              onPressed: onDelete,
            ),
            Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade300),
          ],
        ),
      ),
    );
  }
}

class _EmptyPlans extends StatelessWidget {
  const _EmptyPlans();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bookmark_border, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('저장된 플랜이 없어요',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
          const SizedBox(height: 4),
          Text('대화에서 마음에 드는 플랜을 저장해보세요',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
        ],
      ),
    );
  }
}