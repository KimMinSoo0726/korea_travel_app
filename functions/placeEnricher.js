const LOCAL_URL = "https://naverapihub.apigw.ntruss.com/search/v1/local";
const GEOCODE_URL = "https://maps.apigw.ntruss.com/map-geocode/v2/geocode";

// 호출량 보호용 상한
const MAX_PLACES = 40;   // 한 응답에서 보정할 최대 장소 수
const CONCURRENCY = 5;   // 동시 요청 수

const stripTags = (s) => (s || "").replace(/<[^>]*>/g, "").trim();
const { readCache, writeCache, bumpHits } = require("./placeCache");
/** 지역검색 — 후보 전체를 반환 */
async function searchLocal(query, { clientId, clientSecret }) {
  const url = `${LOCAL_URL}?query=${encodeURIComponent(query)}&display=5&sort=random&format=json`;

  let res;
  try {
    res = await fetch(url, {
      headers: {
        "X-NCP-APIGW-API-KEY-ID": clientId,
        "X-NCP-APIGW-API-KEY": clientSecret,
        Accept: "application/json",
      },
    });
  } catch (e) {
    console.error(`❌ [지역검색] 네트워크 오류: ${e.message}`);
    return [];
  }

  const bodyText = await res.text();
  if (!res.ok) {
    console.error(`❌ [지역검색] HTTP ${res.status} — ${bodyText.slice(0, 300)}`);
    return [];
  }

  try {
    const data = JSON.parse(bodyText);
    return data.items || [];
  } catch {
    console.error(`❌ [지역검색] JSON 파싱 실패`);
    return [];
  }
}

/** 장소 하나 보정 */
async function enrichPlace(ctx, creds) {
  const { name, placeType, region } = ctx;

  // 1차: 지역 + 장소명
  let items = await searchLocal(region ? `${region} ${name}` : name, creds);
  let best = items.length ? pickBest(items, ctx) : null;

  // 2차: 장소명만 (지역명이 방해될 때)
  if (!best) {
    console.log(`🔁 [재시도] 지역명 제외: "${name}"`);
    items = await searchLocal(name, creds);
    best = items.length ? pickBest(items, ctx) : null;
  }

  if (!best) {
    console.warn(`🚫 [보정실패] "${name}"`);
    return null;
  }

  // 좌표: mapx/mapy 우선, 실패 시에만 지오코딩
  const address = best.roadAddress || best.address || null;
  let coord = coordFromMap(best.mapx, best.mapy);
  if (!coord && address) {
    console.log(`📐 [지오코딩 폴백] ${address}`);
    coord = await geocode(address, creds);
  }

  const result = {
    name: stripTags(best.title),
    address,
    roadAddress: best.roadAddress || null,
    jibunAddress: best.address || null,
    category: best.category || null,
    description: stripTags(best.description) || null,
    phone: best.telephone || null,
    homepage: best.link || null,
    lat: coord?.lat ?? null,
    lng: coord?.lng ?? null,
    raw: best,
    verified: true,
  };

  console.log(`💾 [저장] ${result.name} | ${result.category} | ${result.lat}, ${result.lng}`);
  return result;
}

async function geocode(address, { keyId, key }) {
  const url = `${GEOCODE_URL}?query=${encodeURIComponent(address)}`;
  let res;
  try {
    res = await fetch(url, {
      headers: {
        "X-NCP-APIGW-API-KEY-ID": keyId,
        "X-NCP-APIGW-API-KEY": key,
      },
    });
  } catch (e) {
    console.error(`❌ [지오코딩] 네트워크 오류: ${e.message}`);
    return null;
  }

  const bodyText = await res.text();
  if (!res.ok) {
    console.error(`❌ [지오코딩] HTTP ${res.status} — ${bodyText.slice(0, 300)}`);
    return null;
  }

  const data = JSON.parse(bodyText);
  const addr = data.addresses?.[0];
  if (!addr) {
    console.warn(`⚠️ [지오코딩] 결과 없음: ${address}`);
    return null;
  }
  return { lat: parseFloat(addr.y), lng: parseFloat(addr.x) };
}



/** 동시 실행 제한 러너 */
async function runPool(tasks, limit) {
  const results = [];
  let i = 0;
  const workers = Array.from({ length: limit }, async () => {
    while (i < tasks.length) {
      const idx = i++;
      results[idx] = await tasks[idx]().catch((e) => {
        console.warn("보정 오류:", e.message);
        return null;
      });
    }
  });
  await Promise.all(workers);
  return results;
}

async function enrichPlanOptions(planJson, creds, placesCol) {
  if (!planJson?.plans?.length) return planJson;

  const region = planJson.plans[0]?.summary?.destination || "";

  // 이름 → 기대 업종 매핑 수집
  const typeByName = new Map();
  for (const plan of planJson.plans) {
    for (const day of plan.itinerary || []) {
      for (const item of day.items || []) {
        if (item.placeName && !typeByName.has(item.placeName)) {
          typeByName.set(item.placeName, item.placeType || item.category || null);
        }
      }
    }
    for (const acc of plan.accommodations || []) {
      if (acc.name && !typeByName.has(acc.name)) {
        typeByName.set(acc.name, "숙소");
      }
    }
  }
  const allNames = [...typeByName.keys()];

  // 캐시 조회
  let hits = new Map();
  let misses = allNames;
  if (placesCol) {
    try {
      const r = await readCache(placesCol, region, allNames);
      hits = r.hits;
      misses = r.misses;
      console.log(`📦 캐시 ${hits.size}건 / API ${misses.length}건 (전체 ${allNames.length})`);
    } catch (e) {
      console.warn("캐시 조회 실패:", e.message);
    }
  }

  // API 조회
  const toFetch = misses.slice(0, MAX_PLACES);
  const fetched = [];
  if (toFetch.length) {
    const tasks = toFetch.map((n) => () =>
      enrichPlace({ name: n, placeType: typeByName.get(n), region }, creds)
    );
    const results = await runPool(tasks, CONCURRENCY);
    toFetch.forEach((n, i) => {
      hits.set(n, results[i]);
      fetched.push({ name: n, data: results[i] });
    });
    if (placesCol && fetched.length) {
      try {
        await writeCache(placesCol, region, fetched);
        console.log(`💾 캐시 저장 ${fetched.length}건`);
      } catch (e) {
        console.warn("캐시 저장 실패:", e.message);
      }
    }
  }



  const apply = (obj, key) => {
    const got = hits.get(obj[key]);
    if (!got) return;
    const copy = [
      "address", "lat", "lng", "phone", "homepage", "description",
      "thumbnail", "images", "businessHours", "closedDay", "parking",
      "useFee", "menu", "seat", "packing", "reservation",
      "checkIn", "checkOut", "petAllowed", "creditCard", "tourContentId",
    ];
    for (const f of copy) {
      if (got[f] != null && got[f] !== "") obj[f] = got[f];
    }
    if (got.category && !obj.category) obj.category = got.category;
    obj.verified = true;
  };

  for (const plan of planJson.plans) {
    for (const day of plan.itinerary || []) {
      for (const item of day.items || []) apply(item, "placeName");
    }
    for (const acc of plan.accommodations || []) apply(acc, "name");
  }

  if (placesCol) bumpHits(placesCol, region, allNames).catch(() => {});
  return planJson;
}
// ── 문자열 정규화 (공백·기호 제거, 소문자) ──
function norm(s) {
  return (s || "")
    .replace(/<[^>]*>/g, "")
    .toLowerCase()
    .replace(/[\s·,()[\]{}'"`~!@#$%^&*\-_=+./\\]/g, "");
}

// ── 기대 업종 → 네이버 카테고리 키워드 ──
const CATEGORY_HINTS = {
  음식점: ["음식점", "한식", "일식", "중식", "양식", "분식", "고기", "해물", "뷔페", "치킨"],
  맛집: ["음식점", "한식", "일식", "중식", "양식", "해물"],
  카페: ["카페", "디저트", "베이커리", "커피"],
  관광지: ["여행", "명소", "관광", "공원", "해수욕장", "전망", "사찰", "박물관", "미술관", "문화"],
  미술관: ["미술관", "갤러리", "전시", "문화"],
  박물관: ["박물관", "전시", "문화", "역사"],
  문화재: ["문화재", "유적", "사찰", "고궁", "서원", "향교", "史"],
  시장: ["시장", "전통시장", "쇼핑"],
  숙소: ["숙박", "호텔", "펜션", "모텔", "게스트하우스", "리조트"],
  쇼핑: ["쇼핑", "백화점", "아울렛", "시장"],
};

// ── 명백히 무관한 업종 (감점) ──
const IRRELEVANT = [
  "안경원", "PC방", "부동산", "병원", "의원", "약국", "편의점",
  "미용실", "학원", "은행", "구조대", "소방서", "주차장", "세탁",
];

/**
 * 후보 하나에 점수를 매긴다.
 */
function scoreCandidate(item, { name, placeType, region }) {
  const title = stripTags(item.title);
  const nTitle = norm(title);
  const nName = norm(name);
  let score = 0;
  const why = [];

  // 1) 이름 유사도
  if (nTitle === nName) { score += 100; why.push("정확일치+100"); }
  else if (nTitle.startsWith(nName)) { score += 60; why.push("접두일치+60"); }
  else if (nTitle.includes(nName)) { score += 40; why.push("포함+40"); }
  else if (nName.includes(nTitle)) { score += 30; why.push("역포함+30"); }
  else { score -= 20; why.push("불일치-20"); }

  // 2) 군더더기(지점명 등) 패널티
  const diff = Math.abs(nTitle.length - nName.length);
  if (diff > 0) {
    const p = Math.min(diff * 4, 40);
    score -= p;
    why.push(`길이차-${p}`);
  }

  // 3) 업종 적합도
  const cat = item.category || "";
  const hints = CATEGORY_HINTS[placeType] || [];
  if (hints.length && hints.some((h) => cat.includes(h))) {
    score += 35;
    why.push("업종일치+35");
  } else if (IRRELEVANT.some((w) => cat.includes(w))) {
    score -= 50;
    why.push("무관업종-50");
  }

  // 4) 지역 일치
  const addr = item.roadAddress || item.address || "";
  const regionKey = (region || "").replace(/(광역시|특별시|자치도|도|시|군|구)$/g, "");
  if (regionKey && addr.includes(regionKey)) {
    score += 20;
    why.push("지역일치+20");
  }

  return { score, why: why.join(" ") };
}

/**
 * 후보 목록에서 최적 하나 선택 (임계값 미달이면 null)
 */
function pickBest(items, ctx, threshold = 30) {
  const scored = items.map((it) => {
    const { score, why } = scoreCandidate(it, ctx);
    return { item: it, score, why };
  });
  scored.sort((a, b) => b.score - a.score);

  console.log(`🎯 [매칭] "${ctx.name}" (기대업종: ${ctx.placeType || "없음"})`);
  scored.slice(0, 3).forEach((s, i) => {
    console.log(
      `   ${i + 1}. [${s.score}] ${stripTags(s.item.title)} | ${s.item.category} | ${s.why}`
    );
  });

  const best = scored[0];
  if (!best || best.score < threshold) {
    console.warn(`   ⚠️ 임계값(${threshold}) 미달 → 매칭 포기`);
    return null;
  }
  console.log(`   ✅ 선택: ${stripTags(best.item.title)}`);
  return best.item;
}

// ── mapx/mapy → WGS84 좌표 ──
function coordFromMap(mapx, mapy) {
  const x = Number(mapx);
  const y = Number(mapy);
  if (!x || !y) return null;
  if (x > 1000000) return { lat: y / 1e7, lng: x / 1e7 };
  return null;
}


module.exports = { enrichPlanOptions, enrichPlace };