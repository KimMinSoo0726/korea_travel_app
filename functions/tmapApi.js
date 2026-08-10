const BASE = "https://apis.openapi.sk.com";

async function tmapGet(path, params, appKey) {
  const qs = new URLSearchParams(params).toString();
  let res;
  try {
    res = await fetch(`${BASE}${path}?${qs}`, {
      headers: { appKey, Accept: "application/json" },
    });
  } catch (e) {
    console.error(`❌ [Tmap] 네트워크: ${e.message}`);
    return null;
  }
  const text = await res.text();
  if (!res.ok) {
    console.error(`❌ [Tmap] HTTP ${res.status} — ${text.slice(0, 250)}`);
    return null;
  }
  try { return JSON.parse(text); } catch { return null; }
}

async function tmapPost(path, params, body, appKey) {
  const qs = new URLSearchParams(params).toString();
  let res;
  try {
    res = await fetch(`${BASE}${path}${qs ? "?" + qs : ""}`, {
      method: "POST",
      headers: {
        appKey,
        Accept: "application/json",
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    });
  } catch (e) {
    console.error(`❌ [Tmap] 네트워크: ${e.message}`);
    return null;
  }
  const text = await res.text();
  if (!res.ok) {
    console.error(`❌ [Tmap] HTTP ${res.status} — ${text.slice(0, 300)}`);
    return null;
  }
  try { return JSON.parse(text); } catch { return null; }
}

// ───────── 장소 검색 ─────────

/** POI 통합검색 */
async function searchPoi(keyword, appKey, { lat, lng, radius } = {}) {
  const params = {
    version: 1,
    searchKeyword: keyword,
    resCoordType: "WGS84GEO",
    reqCoordType: "WGS84GEO",
    searchType: "all",
    count: 10,
    page: 1,
  };
  if (lat != null && lng != null) {
    params.centerLat = lat;
    params.centerLon = lng;
    if (radius) params.radius = Math.min(Math.round(radius / 1000), 33); // km
  }

  const data = await tmapGet("/tmap/pois", params, appKey);
  const pois = data?.searchPoiInfo?.pois?.poi;
  const list = !pois ? [] : Array.isArray(pois) ? pois : [pois];
  console.log(`🔍 [Tmap] "${keyword}" → ${list.length}건`);
  return list;
}

/** POI → 표준 형태로 정규화 */
function normalizePoi(p) {
  const upper = p.upperAddrName || "";
  const middle = p.middleAddrName || "";
  const lower = p.lowerAddrName || "";
  const road =
    p.roadName && p.firstBuildNo
      ? `${upper} ${middle} ${p.roadName} ${p.firstBuildNo}${
          p.secondBuildNo && p.secondBuildNo !== "0" ? "-" + p.secondBuildNo : ""
        }`.trim()
      : null;
  const jibun =
    lower && p.firstNo
      ? `${upper} ${middle} ${lower} ${p.firstNo}${
          p.secondNo && p.secondNo !== "0" ? "-" + p.secondNo : ""
        }`.trim()
      : `${upper} ${middle} ${lower}`.trim();

  return {
    poiId: String(p.id),
    pkey: p.pkey ? String(p.pkey) : null,
    name: p.name || "",
    tel: p.telNo || null,
    lat: parseFloat(p.frontLat || p.noorLat),
    lng: parseFloat(p.frontLon || p.noorLon),
    roadAddress: road,
    jibunAddress: jibun || null,
    zipcode: p.zipCode || null,
    region: upper || null,
    sigungu: middle || null,
    bizUpper: p.upperBizName || null,
    bizMiddle: p.middleBizName || null,
    bizLower: p.lowerBizName || null,
    categoryName: [p.upperBizName, p.middleBizName, p.lowerBizName]
      .filter(Boolean)
      .join(" > ") || null,
    parkFlag: p.parkFlag === "1",
    raw: p,
  };
}

// ───────── 경로 ─────────

/** 자동차 (경유지 최대 5) */
async function routeCar(points, appKey) {
  const s = points[0];
  const e = points[points.length - 1];
  const via = points.slice(1, -1).slice(0, 5);

  const body = {
    startX: s.lng, startY: s.lat,
    endX: e.lng, endY: e.lat,
    reqCoordType: "WGS84GEO",
    resCoordType: "WGS84GEO",
    searchOption: "0",
    trafficInfo: "N",
    startName: "출발", endName: "도착",
  };
  if (via.length) {
    body.passList = via.map((p) => `${p.lng},${p.lat}`).join("_");
  }

  const data = await tmapPost("/tmap/routes", { version: 1 }, body, appKey);
  return parseGeoJson(data);
}

/** 보행 (경유지 미지원 → 구간별로 이어붙임) */
async function routeWalk(points, appKey) {
  const legs = [];
  let totalDist = 0;
  let totalTime = 0;

  for (let i = 0; i < points.length - 1 && i < 8; i++) {
    const s = points[i];
    const e = points[i + 1];
    const data = await tmapPost(
      "/tmap/routes/pedestrian",
      { version: 1 },
      {
        startX: s.lng, startY: s.lat,
        endX: e.lng, endY: e.lat,
        reqCoordType: "WGS84GEO",
        resCoordType: "WGS84GEO",
        startName: encodeURIComponent("출발"),
        endName: encodeURIComponent("도착"),
        searchOption: "0",
      },
      appKey
    );
    const r = parseGeoJson(data);
    legs.push(...r.path);
    totalDist += r.distance;
    totalTime += r.duration;
  }
  return { path: legs, distance: totalDist, duration: totalTime, mode: "walk" };
}

/** 대중교통 (2지점만 — 구간별 반복) */
async function routeTransit(points, appKey) {
  const path = [];
  let totalDist = 0;
  let totalTime = 0;
  const summary = [];
  for (let i = 0; i < points.length - 1 && i < 6; i++) {
    const s = points[i];
    const e = points[i + 1];
    const data = await tmapPost(
      "/transit/routes",
      {},
      {
        startX: String(s.lng), startY: String(s.lat),
        endX: String(e.lng), endY: String(e.lat),
        count: 1, lang: 0, format: "json",
      },
      appKey
    );

    const it = data?.metaData?.plan?.itineraries?.[0];
    if (!it) {
      console.warn(`⚠️ [Tmap] 대중교통 경로 없음 (구간 ${i + 1})`);
      continue;
    }
    totalDist += it.totalDistance || 0;
    totalTime += (it.totalTime || 0) * 1000; // 초 → ms

    for (const leg of it.legs || []) {
      // 도보 구간
      if (leg.mode === "WALK") {
        for (const st of leg.steps || []) {
          path.push(...parseLineString(st.linestring));
        }
      } else if (leg.passShape?.linestring) {
        path.push(...parseLineString(leg.passShape.linestring));
      }
      if (leg.mode !== "WALK") {
        summary.push({
          mode: leg.mode,
          route: leg.route || null,
          from: leg.start?.name || null,
          to: leg.end?.name || null,
          sectionTime: leg.sectionTime || 0,
        });
      }
    }
  }

  return { path, distance: totalDist, duration: totalTime, mode: "transit", legs: summary };
}

/** "lng,lat lng,lat" → [[lng,lat], ...] */
function parseLineString(str) {
  if (!str) return [];
  return str
    .trim()
    .split(" ")
    .map((pair) => {
      const [x, y] = pair.split(",").map(Number);
      return [x, y];
    })
    .filter(([x, y]) => !isNaN(x) && !isNaN(y));
}

/** Tmap GeoJSON → path/distance/duration */
function parseGeoJson(data) {
  const feats = data?.features || [];
  const path = [];
  let distance = 0;
  let duration = 0;

  for (const f of feats) {
    if (f.geometry?.type === "LineString") {
      path.push(...f.geometry.coordinates);
    }
    if (f.properties?.totalDistance) distance = f.properties.totalDistance;
    if (f.properties?.totalTime) duration = f.properties.totalTime * 1000;
  }
  return { path, distance, duration };
}

/** 보행 GeoJSON → path + 턴바이턴 안내 */
function parseWalkDetailed(data) {
  const feats = data?.features || [];
  const path = [];
  const steps = [];
  let distance = 0;
  let duration = 0;

  for (const f of feats) {
    const p = f.properties || {};
    if (f.geometry?.type === "LineString") {
      path.push(...f.geometry.coordinates);
      if (p.description) {
        steps.push({
          description: p.description,
          streetName: p.name || null,
          distance: p.distance || 0,
          time: p.time || 0,
        });
      }
    } else if (f.geometry?.type === "Point") {
      if (p.totalDistance) distance = p.totalDistance;
      if (p.totalTime) duration = p.totalTime * 1000;
      // 출발/도착/회전 안내 (LineString에 없는 것만)
      if (p.pointType === "SP" || p.pointType === "EP") {
        steps.push({
          description: p.pointType === "SP" ? "출발" : "도착",
          streetName: p.name || null,
          distance: 0,
          time: 0,
          marker: p.pointType,
        });
      }
    }
  }
  return { path, distance, duration, steps };
}

/** 한 구간 보행 (상세 포함) */
async function walkLeg(s, e, appKey) {
  const data = await tmapPost(
    "/tmap/routes/pedestrian",
    { version: 1 },
    {
      startX: s.lng, startY: s.lat,
      endX: e.lng, endY: e.lat,
      reqCoordType: "WGS84GEO", resCoordType: "WGS84GEO",
      startName: "출발", endName: "도착", searchOption: "0",
    },
    appKey
  );
  if (!data || data.error) return null;
  const r = parseWalkDetailed(data);
  return r.path.length ? r : null;
}

/** 보행 전체 */
async function routeWalk(points, appKey) {
  const path = [];
  const legs = [];
  let totalDist = 0;
  let totalTime = 0;

  for (let i = 0; i < points.length - 1 && i < 8; i++) {
    const r = await walkLeg(points[i], points[i + 1], appKey);
    if (!r) {
      console.warn(`   ⚠️ 보행 구간 ${i + 1} 실패`);
      continue;
    }
    console.log(`   ✓ 구간 ${i + 1}: ${r.distance}m, ${Math.round(r.duration / 60000)}분`);
    path.push(...r.path);
    totalDist += r.distance;
    totalTime += r.duration;
    legs.push({
      order: i,
      mode: "WALK",
      fromName: points[i].name || `${i + 1}번 장소`,
      toName: points[i + 1].name || `${i + 2}번 장소`,
      distance: r.distance,
      sectionTime: Math.round(r.duration / 1000),
      steps: r.steps,
    });
  }

  return {
    path, distance: totalDist, duration: totalTime,
    mode: "walk", legs, transferCount: 0,
    totalWalkDistance: totalDist,
    totalWalkTime: Math.round(totalTime / 1000),
  };
}

/** 한 구간 대중교통 (상세 포함) */
async function transitLeg(s, e, appKey) {
  const data = await tmapPost(
    "/transit/routes", {},
    {
      startX: String(s.lng), startY: String(s.lat),
      endX: String(e.lng), endY: String(e.lat),
      count: 1, lang: 0, format: "json",
    },
    appKey
  );

  if (data?.error?.code === "INVALID_API_KEY") return { unauthorized: true };
  const rc = data?.result?.status;
  if (rc && rc !== 0) {
    console.warn(`   ⚠️ 대중교통 result=${rc} ${data?.result?.message || ""}`);
    return null;
  }

  const it = data?.metaData?.plan?.itineraries?.[0];
  if (!it) return null;

  const path = [];
  const legs = [];

  for (const leg of it.legs || []) {
    const base = {
      mode: leg.mode,
      sectionTime: leg.sectionTime || 0,
      distance: leg.distance || 0,
      fromName: leg.start?.name || null,
      toName: leg.end?.name || null,
    };

    if (leg.mode === "WALK") {
      const stepPath = [];
      const steps = [];
      for (const st of leg.steps || []) {
        const pts = parseLineString(st.linestring);
        stepPath.push(...pts);
        steps.push({
          description: st.description,
          streetName: st.streetName || null,
          distance: st.distance || 0,
        });
      }
      path.push(...stepPath);
      legs.push({ ...base, steps });
    } else {
      const pts = parseLineString(leg.passShape?.linestring);
      path.push(...pts);
      legs.push({
        ...base,
        route: leg.route || null,          // "지선:1128"
        routeColor: leg.routeColor || null,
        routeType: leg.type || null,
        stations: (leg.passStopList?.stationList || []).map((s) => ({
          name: s.stationName,
          lat: parseFloat(s.lat),
          lng: parseFloat(s.lon),
        })),
      });
    }
  }

  return {
    path,
    distance: it.totalDistance || 0,
    duration: (it.totalTime || 0) * 1000,
    legs,
    fare: it.fare?.regular?.totalFare ?? 0,
    transferCount: it.transferCount || 0,
    totalWalkTime: it.totalWalkTime || 0,
    totalWalkDistance: it.totalWalkDistance || 0,
  };
}

/** 대중교통 전체 (실패 구간은 도보 폴백) */
async function routeTransit(points, appKey) {
  const path = [];
  const allLegs = [];
  let totalDist = 0, totalTime = 0, fare = 0;
  let transferCount = 0, walkTime = 0, walkDist = 0;
  let okTransit = 0, okWalk = 0, failed = 0;
  let unauthorized = false;

  for (let i = 0; i < points.length - 1 && i < 6; i++) {
    const s = points[i];
    const e = points[i + 1];
    let r = null;
    let isWalkFallback = false;

    if (!unauthorized) {
      const t = await transitLeg(s, e, appKey);
      if (t?.unauthorized) {
        unauthorized = true;
        console.error("❌ 대중교통 권한 없음 → 도보로 대체");
      } else if (t) {
        r = t;
        okTransit++;
        fare += t.fare;
        transferCount += t.transferCount;
        walkTime += t.totalWalkTime;
        walkDist += t.totalWalkDistance;
      }
    }

    if (!r) {
      const w = await walkLeg(s, e, appKey);
      if (w) {
        r = { ...w, legs: [{ mode: "WALK", steps: w.steps,
              distance: w.distance, sectionTime: Math.round(w.duration / 1000) }] };
        isWalkFallback = true;
        okWalk++;
      } else {
        failed++;
        console.warn(`   ⚠️ 구간 ${i + 1} 경로 없음`);
        continue;
      }
    }

    path.push(...r.path);
    totalDist += r.distance;
    totalTime += r.duration;

    allLegs.push({
      order: i,
      segmentFrom: s.name || `${i + 1}번 장소`,
      segmentTo: e.name || `${i + 2}번 장소`,
      fallbackWalk: isWalkFallback,
      legs: r.legs || [],
    });
  }

  console.log(`🚇 [대중교통] 성공 ${okTransit} / 도보대체 ${okWalk} / 실패 ${failed}`);

  return {
    path, distance: totalDist, duration: totalTime, mode: "transit",
    segments: allLegs, fare, transferCount,
    totalWalkTime: walkTime, totalWalkDistance: walkDist,
    fallbackWalk: okWalk, transitUnavailable: unauthorized,
  };
}

module.exports = { searchPoi, normalizePoi, routeCar, routeWalk, routeTransit };