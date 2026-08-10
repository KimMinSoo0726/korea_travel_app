import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/travel_plan.dart';
import '../../../core/constants/app_constants.dart';

Future<void> showPlaceDetail(BuildContext context, PlanItem item) {
  return showDialog(
    context: context,
    builder: (_) => PlaceDetailDialog(item: item),
  );
}

class PlaceDetailDialog extends StatelessWidget {
  final PlanItem item;
  const PlaceDetailDialog({super.key, required this.item});

  Future<void> _open(BuildContext context, String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('링크를 열 수 없습니다.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 헤더
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.06),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.placeName ?? item.activity,
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          children: [
                            if (item.placeType != null)
                              _chip(theme, item.placeType!),
                            if (item.category != null)
                              _chip(theme, item.category!),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

           // 본문
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ★ 사진 갤러리
                    if (item.images.isNotEmpty)
                      SizedBox(
                        height: 160,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: item.images.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                           itemBuilder: (_, i) => ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              AppConstants.proxyImage(item.images[i]),   // ★
                              width: 220,
                              height: 160,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 220,
                                color: Colors.grey.shade100,
                                alignment: Alignment.center,
                                child: Icon(Icons.image_not_supported,
                                    color: Colors.grey.shade300),
                              ),
                              loadingBuilder: (c, w, p) => p == null
                                  ? w
                                  : Container(
                                      width: 220,
                                      color: Colors.grey.shade100,
                                      alignment: Alignment.center,
                                      child: const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (item.description != null) ...[
                            Text(item.description!,
                                style:
                                    const TextStyle(fontSize: 14, height: 1.5)),
                            const SizedBox(height: 16),
                          ],
                          _row(Icons.schedule, '방문 시각', item.time),
                          if (item.durationLabel.isNotEmpty)
                            _row(Icons.timelapse, '머무는 시간',
                                item.durationLabel),
                          if (item.avgPrice > 0)
                            _row(Icons.payments_outlined, '1인 평균',
                                wonFormat(item.avgPrice)),
                          if (item.menu != null)
                            _row(Icons.restaurant_menu, '대표 메뉴', item.menu!),
                          if (item.address != null)
                            _row(Icons.place_outlined, '주소', item.address!),
                          if (item.businessHours != null)
                            _row(Icons.access_time, '영업시간',
                                item.businessHours!),
                          if (item.closedDay != null)
                            _row(Icons.event_busy, '휴무일', item.closedDay!),
                          if (item.useFee != null)
                            _row(Icons.confirmation_number_outlined, '이용요금',
                                item.useFee!),
                          if (item.parking != null)
                            _row(Icons.local_parking, '주차', item.parking!),
                          if (item.checkIn != null)
                            _row(Icons.login, '체크인', item.checkIn!),
                          if (item.checkOut != null)
                            _row(Icons.logout, '체크아웃', item.checkOut!),
                          if (item.petAllowed != null)
                            _row(Icons.pets, '반려동물', item.petAllowed!),
                          if (item.phone != null)
                            _row(Icons.call_outlined, '전화', item.phone!),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 액션 버튼
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (item.searchUrl != null)
                    OutlinedButton.icon(
                      onPressed: () => _open(context, item.searchUrl),
                      icon: const Icon(Icons.search, size: 16),
                      label: const Text('네이버 검색'),
                    ),
                  if (item.photoSearchUrl != null)
                    OutlinedButton.icon(
                      onPressed: () => _open(context, item.photoSearchUrl),
                      icon: const Icon(Icons.photo_outlined, size: 16),
                      label: const Text('사진 보기'),
                    ),
                  if (item.homepage != null)
                    OutlinedButton.icon(
                      onPressed: () => _open(context, item.homepage),
                      icon: const Icon(Icons.public, size: 16),
                      label: const Text('홈페이지'),
                    ),
                  if (item.placeName != null)
                    FilledButton.tonalIcon(
                      onPressed: () => _open(
                        context,
                        'https://map.naver.com/p/search/'
                        '${Uri.encodeComponent(item.placeName!)}',
                      ),
                      icon: const Icon(Icons.place, size: 16),
                      label: const Text('네이버 지도'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(ThemeData theme, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withOpacity(0.14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600)),
      );

  Widget _row(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: Colors.grey.shade400),
            const SizedBox(width: 10),
            SizedBox(
              width: 68,
              child: Text(label,
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ),
            Expanded(
                child: Text(value, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );
}