import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../../models/travel_plan.dart';

@JS('renderDayMap')
external void _renderDayMap(String elementId, String pointsJson);

@JS('focusMapMarker')
external void _focusMapMarker(String elementId, int index);

@JS('resetMapView')
external void _resetMapView(String elementId);

@JS('drawRoutePath')
external void _drawRoutePath(String elementId, String pathJson);

@JS('refreshMapMarkers')
external void _refreshMapMarkers(String elementId, String pointsJson);

void focusMarker(String id, int index) => _focusMapMarker(id, index);
void resetView(String id) => _resetMapView(id);
void drawRoute_(String id, List<List<double>> path) =>
    _drawRoutePath(id, jsonEncode(path));

bool _registered = false;
const String _viewType = 'naver-map-view';

void _ensureFactory() {
  if (_registered) return;
  ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
    final div = web.document.createElement('div') as web.HTMLDivElement;
    div.id = 'naver-map-$viewId';
    div.style.width = '100%';
    div.style.height = '100%';
    return div;
  });
  _registered = true;
}

Widget buildNaverMap(List<PlanItem> points, void Function(String id) onReady) {
  _ensureFactory();

  final payload = jsonEncode(points
      .map((p) => {
            'lat': p.lat,
            'lng': p.lng,
            'name': p.placeName ?? p.activity,
            'time': p.time,
          })
      .toList());

  return HtmlElementView(
    viewType: _viewType,
    onPlatformViewCreated: (int id) {
      final elementId = 'naver-map-$id';
      Future.delayed(const Duration(milliseconds: 100), () {
        _renderDayMap(elementId, payload);
        onReady(elementId);
      });
    },
  );
}

void refreshMarkers(String id, List<PlanItem> points) {
  final payload = jsonEncode(points
      .map((p) => {
            'lat': p.lat,
            'lng': p.lng,
            'name': p.placeName ?? p.activity,
            'time': p.time,
          })
      .toList());
  _refreshMapMarkers(id, payload);
}