import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/trip_settings.dart';
import '../../providers/api_provider.dart';

class PreferencesScreen extends ConsumerStatefulWidget {
  const PreferencesScreen({super.key});

  @override
  ConsumerState<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends ConsumerState<PreferencesScreen> {
  TravelPreferences _prefs = const TravelPreferences();
  bool _loading = true;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await ref.read(apiServiceProvider).getUserPrefs();
      if (mounted) setState(() => _prefs = p);
    } catch (e) {
      debugPrint('취향 로드 실패: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _update(TravelPreferences p) async {
    setState(() {
      _prefs = p;
      _saved = false;
    });
    try {
      await ref.read(apiServiceProvider).saveUserPrefs(p);
      if (mounted) setState(() => _saved = true);
    } catch (e) {
      debugPrint('취향 저장 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      children: [
        Row(
          children: [
            Text('여행 취향 설정',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const Spacer(),
            if (_saved)
              Row(children: [
                Icon(Icons.check_circle,
                    size: 14, color: Colors.green.shade600),
                const SizedBox(width: 4),
                Text('저장됨',
                    style: TextStyle(
                        fontSize: 12, color: Colors.green.shade600)),
              ]),
          ],
        ),
        const SizedBox(height: 4),
        Text('설정한 취향은 모든 새 대화에 자동으로 반영됩니다.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        const SizedBox(height: 28),

        // ── 여행 강도 ──
        _sectionTitle(theme, '🔥 여행 강도', '하루에 얼마나 많은 일정을 소화할지'),
        const SizedBox(height: 10),
        Row(
          children: TravelPreferences.paceOptions.entries.map((e) {
            final sel = _prefs.pace == e.key;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  onTap: () => _update(_prefs.copyWith(pace: e.key)),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: sel
                          ? theme.colorScheme.primary.withOpacity(0.1)
                          : Colors.white,
                      border: Border.all(
                        color: sel
                            ? theme.colorScheme.primary
                            : Colors.grey.shade300,
                        width: sel ? 1.6 : 1,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text(_paceEmoji(e.key),
                            style: const TextStyle(fontSize: 22)),
                        const SizedBox(height: 6),
                        Text(e.value,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight:
                                    sel ? FontWeight.bold : FontWeight.normal,
                                color: sel
                                    ? theme.colorScheme.primary
                                    : Colors.grey.shade700)),
                        const SizedBox(height: 2),
                        Text(_paceDesc(e.key),
                            style: TextStyle(
                                fontSize: 10.5, color: Colors.grey.shade500)),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 28),

        // ── 관심사 ──
        _sectionTitle(theme, '💛 관심사', '여러 개 선택할 수 있어요'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: TravelPreferences.interestOptions.map((i) {
            final sel = _prefs.interests.contains(i);
            return FilterChip(
              label: Text(i, style: const TextStyle(fontSize: 13)),
              selected: sel,
              showCheckmark: false,
              avatar: Text(_interestEmoji(i),
                  style: const TextStyle(fontSize: 14)),
              onSelected: (v) {
                final list = [..._prefs.interests];
                v ? list.add(i) : list.remove(i);
                _update(_prefs.copyWith(interests: list));
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 28),

        // ── 계획 방식 ──
        _sectionTitle(theme, '🗂 계획 방식', 'AI가 얼마나 주도할지'),
        const SizedBox(height: 10),
        ...TravelPreferences.planningOptions.entries.map((e) {
          final sel = _prefs.planningMode == e.key;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () => _update(_prefs.copyWith(planningMode: e.key)),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: sel
                      ? theme.colorScheme.primary.withOpacity(0.08)
                      : Colors.white,
                  border: Border.all(
                    color:
                        sel ? theme.colorScheme.primary : Colors.grey.shade300,
                    width: sel ? 1.6 : 1,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      sel
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: sel
                          ? theme.colorScheme.primary
                          : Colors.grey.shade400,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.value,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: sel
                                      ? FontWeight.bold
                                      : FontWeight.normal)),
                          const SizedBox(height: 2),
                          Text(
                            e.key == 'planned'
                                ? '조건을 하나씩 물어보며 함께 만들어요'
                                : '취향에 맞게 완성된 코스를 바로 제안해요',
                            style: TextStyle(
                                fontSize: 11.5, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _sectionTitle(ThemeData theme, String title, String desc) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(desc,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ],
      );

  String _paceEmoji(String k) =>
      k == 'packed' ? '🏃' : (k == 'relaxed' ? '🌿' : '🚶');
  String _paceDesc(String k) =>
      k == 'packed' ? '하루 8곳+' : (k == 'relaxed' ? '하루 3곳' : '하루 5곳');

  String _interestEmoji(String i) {
    switch (i) {
      case '미식': return '🍜';
      case '문화재': return '🏯';
      case '미술관': return '🎨';
      case '박물관': return '🏛';
      case '시장': return '🛒';
      case '카페': return '☕';
      case '풍경': return '🏞';
      case '액티비티': return '🏄';
      case '쇼핑': return '🛍';
      case '야경': return '🌃';
      default: return '📍';
    }
  }
}

