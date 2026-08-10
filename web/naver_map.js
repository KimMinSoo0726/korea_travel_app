window.__maps = {};

/** 지도 렌더링 */
window.renderDayMap = function (elementId, pointsJson) {
  const tryRender = (retry) => {
    const el = document.getElementById(elementId);
    if (!el || !window.naver || !naver.maps) {
      if (retry > 0) return setTimeout(() => tryRender(retry - 1), 200);
      return;
    }

    let points;
    try { points = JSON.parse(pointsJson); } catch (e) { return; }

    const valid = points.filter(
      (p) => typeof p.lat === "number" && typeof p.lng === "number"
    );
    if (valid.length === 0) {
      el.innerHTML =
        '<div style="display:flex;align-items:center;justify-content:center;' +
        'height:100%;color:#999;font-size:13px;">표시할 좌표가 없습니다</div>';
      return;
    }

    const map = new naver.maps.Map(el, {
      center: new naver.maps.LatLng(valid[0].lat, valid[0].lng),
      zoom: 13,
      scrollWheel: false,        // ★ 휠 줌 끔 — 페이지 스크롤 우선
      pinchZoom: true,
      draggable: true,
      scaleControl: false,
      mapDataControl: false,
      zoomControl: true,
      zoomControlOptions: { position: naver.maps.Position.TOP_RIGHT },
    });

    const bounds = new naver.maps.LatLngBounds();
    const path = [];
    const markers = [];
    const infos = [];

    valid.forEach((p, i) => {
      const pos = new naver.maps.LatLng(p.lat, p.lng);
      bounds.extend(pos);
      path.push(pos);

      const marker = new naver.maps.Marker({
        position: pos,
        map: map,
        zIndex: 100,
        icon: {
          content: markerHtml(i + 1, false),
          anchor: new naver.maps.Point(14, 14),
        },
      });

      const info = new naver.maps.InfoWindow({
        content:
          '<div style="padding:8px 12px;font-size:13px;min-width:130px;">' +
          '<b>' + (i + 1) + '. ' + (p.name || "") + "</b><br/>" +
          '<span style="color:#888;font-size:11px;">' + (p.time || "") + "</span>" +
          "</div>",
        borderWidth: 0,
        backgroundColor: "#fff",
      });

      naver.maps.Event.addListener(marker, "click", () => {
        infos.forEach((x) => x.close());
        info.open(map, marker);
      });

      markers.push(marker);
      infos.push(info);
    });

    // 임시 직선 경로 (실제 경로 도착 전까지)
    let line = new naver.maps.Polyline({
      map: map,
      path: path,
      strokeColor: "#B0BEC5",
      strokeWeight: 2,
      strokeOpacity: 0.7,
      strokeStyle: "shortdash",
    });

    window.__maps[elementId] = { map, markers, infos, bounds, line, path };

    if (valid.length > 1) {
      map.fitBounds(bounds, { top: 50, right: 50, bottom: 40, left: 40 });
    }

    addResetButton(el, elementId);
  };

  tryRender(25);
};

function markerHtml(n, active) {
  const bg = active ? "#E65100" : "#2E7D6B";
  const size = active ? 34 : 28;
  const font = active ? 14 : 12;
  return (
    '<div style="background:' + bg + ';color:#fff;width:' + size + 'px;height:' + size +
    'px;border-radius:50%;display:flex;align-items:center;justify-content:center;' +
    'font-size:' + font + 'px;font-weight:700;border:2px solid #fff;' +
    'box-shadow:0 2px 6px rgba(0,0,0,.35);">' + n + "</div>"
  );
}

/** 전체보기 버튼 */
function addResetButton(el, elementId) {
  if (el.querySelector(".map-reset-btn")) return;
  const btn = document.createElement("button");
  btn.className = "map-reset-btn";
  btn.textContent = "전체보기";
  btn.style.cssText =
    "position:absolute;left:10px;bottom:10px;z-index:1000;padding:6px 12px;" +
    "font-size:12px;border:1px solid #ddd;border-radius:16px;background:#fff;" +
    "cursor:pointer;box-shadow:0 1px 4px rgba(0,0,0,.2);";
  btn.onclick = (e) => {
    e.stopPropagation();
    window.resetMapView(elementId);
  };
  el.style.position = "relative";
  el.appendChild(btn);
}

/** 전체 범위로 복귀 */
window.resetMapView = function (elementId) {
  const s = window.__maps[elementId];
  if (!s) return;
  s.infos.forEach((x) => x.close());
  s.markers.forEach((m, i) =>
    m.setIcon({ content: markerHtml(i + 1, false), anchor: new naver.maps.Point(14, 14) })
  );
  if (s.markers.length > 1) {
    s.map.fitBounds(s.bounds, { top: 50, right: 50, bottom: 40, left: 40 });
  } else if (s.markers.length === 1) {
    s.map.setCenter(s.markers[0].getPosition());
    s.map.setZoom(15);
  }
};

/** 특정 마커로 이동 + 강조 */
window.focusMapMarker = function (elementId, index) {
  const s = window.__maps[elementId];
  if (!s || !s.markers[index]) return;

  s.markers.forEach((m, i) =>
    m.setIcon({
      content: markerHtml(i + 1, i === index),
      anchor: new naver.maps.Point(14, 14),
    })
  );
  s.infos.forEach((x) => x.close());

  const marker = s.markers[index];
  s.map.setZoom(16);
  s.map.panTo(marker.getPosition());
  s.infos[index].open(s.map, marker);
};

/** 실제 도로 경로 그리기 */
window.drawRoutePath = function (elementId, pathJson) {
  const s = window.__maps[elementId];
  if (!s) return;
  let coords;
  try { coords = JSON.parse(pathJson); } catch (e) { return; }
  if (!coords || coords.length < 2) return;

  const latlngs = coords.map((c) => new naver.maps.LatLng(c[1], c[0]));
  if (s.line) s.line.setMap(null);
  s.line = new naver.maps.Polyline({
    map: s.map,
    path: latlngs,
    strokeColor: "#2E7D6B",
    strokeWeight: 4,
    strokeOpacity: 0.85,
  });
};

/** 마커 전체 다시 그리기 */
window.refreshMapMarkers = function (elementId, pointsJson) {
  const s = window.__maps[elementId];
  if (!s) return;

  let points;
  try { points = JSON.parse(pointsJson); } catch (e) { return; }
  const valid = points.filter(
    (p) => typeof p.lat === "number" && typeof p.lng === "number"
  );

  // 기존 마커/인포/경로 제거
  s.markers.forEach((m) => m.setMap(null));
  s.infos.forEach((i) => i.close());
  if (s.line) s.line.setMap(null);

  s.markers = [];
  s.infos = [];
  s.path = [];
  s.bounds = new naver.maps.LatLngBounds();

  if (valid.length === 0) return;

  valid.forEach((p, i) => {
    const pos = new naver.maps.LatLng(p.lat, p.lng);
    s.bounds.extend(pos);
    s.path.push(pos);

    const marker = new naver.maps.Marker({
      position: pos,
      map: s.map,
      zIndex: 100,
      icon: { content: markerHtml(i + 1, false), anchor: new naver.maps.Point(14, 14) },
    });
    const info = new naver.maps.InfoWindow({
      content:
        '<div style="padding:8px 12px;font-size:13px;min-width:130px;">' +
        "<b>" + (i + 1) + ". " + (p.name || "") + "</b><br/>" +
        '<span style="color:#888;font-size:11px;">' + (p.time || "") + "</span></div>",
      borderWidth: 0,
      backgroundColor: "#fff",
    });
    naver.maps.Event.addListener(marker, "click", () => {
      s.infos.forEach((x) => x.close());
      info.open(s.map, marker);
    });
    s.markers.push(marker);
    s.infos.push(info);
  });

  s.line = new naver.maps.Polyline({
    map: s.map,
    path: s.path,
    strokeColor: "#B0BEC5",
    strokeWeight: 2,
    strokeOpacity: 0.7,
    strokeStyle: "shortdash",
  });

  if (valid.length > 1) {
    s.map.fitBounds(s.bounds, { top: 50, right: 50, bottom: 40, left: 40 });
  } else {
    s.map.setCenter(s.markers[0].getPosition());
    s.map.setZoom(15);
  }
};