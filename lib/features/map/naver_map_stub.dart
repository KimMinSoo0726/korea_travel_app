import 'package:flutter/material.dart';
import '../../models/travel_plan.dart';

void focusMarker(String id, int index) {}
void resetView(String id) {}
void drawRoute_(String id, List<List<double>> path) {}

void refreshMarkers(String id, List<PlanItem> points) {}

Widget buildNaverMap(List<PlanItem> points, void Function(String id) onReady) {
  return Container(
    alignment: Alignment.center,
    color: Colors.grey.shade100,
    child: const Text('이 환경에서는 지도를 표시할 수 없습니다',
        style: TextStyle(fontSize: 13)),
  );
}
