const BASE = "https://apis.data.go.kr/B551011/KorService2";
const COMMON = "MobileOS=ETC&MobileApp=KoreaTravel&_type=json";

/** 두 좌표 간 거리(m) */
function distanceM(lat1, lng1, lat2, lng2) {
  const R = 6371000;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

async function callTour(path, params, key) {
  const qs = new URLSearchParams(params).toString();
  const url = `${BASE}/${path}?serviceKey=${encodeURIComponent(key)}&${COMMON}&${qs}`;

  let res;
  try {
    res = await fetch(url);
  } catch (e) {
    console.error(`❌ [TourAPI] 네트워크: ${e.message}`);
    return null;
  }

  const text = await res.text();
  if (!res.ok) {
    console.error(`❌ [TourAPI] HTTP ${res.status} — ${text.slice(0, 200)}`);
    return null;
  }
  // 에러는 XML로 오는 경우가 있음
  if (text.trim().startsWith("<")) {
    console.error(`❌ [TourAPI] XML 오류 — ${text.slice(0, 300)}`);
    return null;
  }

  try {
    const json = JSON.parse(text);
    const header = json.response?.header;
    if (header?.resultCode !== "0000") {
      console.warn(`⚠️ [TourAPI] ${header?.resultCode} ${header?.resultMsg}`);
      return null;
    }
    return json.response?.body;
  } catch {
    console.error(`❌ [TourAPI] JSON 파싱 실패`);
    return null;
  }
}

function toArray(items) {
  if (!items) return [];
  const it = items.item;
  if (!it) return [];
  return Array.isArray(it) ? it : [it];
}

/**
 * 장소명으로 TourAPI 콘텐츠 찾기
 * 네이버 좌표와 300m 이내인 것만 채택 (교차 검증)
 */
async function findContent(name, lat, lng, key) {
  const body = await callTour(
    "searchKeyword2",
    { keyword: name, numOfRows: 10, pageNo: 1, arrange: "A" },
    key
  );
  const items = toArray(body?.items);
  if (items.length === 0) {
    console.log(`🏞 [TourAPI] 결과 없음: "${name}"`);
    return null;
  }

  // 좌표 검증
  if (lat != null && lng != null) {
    for (const it of items) {
      const ty = parseFloat(it.mapy);
      const tx = parseFloat(it.mapx);
      if (!ty || !tx) continue;
      const d = distanceM(lat, lng, ty, tx);
      if (d < 300) {
        console.log(`🏞 [TourAPI] 매칭 ${it.title} (${Math.round(d)}m)`);
        return it;
      }
    }
    console.log(`🏞 [TourAPI] 좌표 불일치로 제외: "${name}"`);
    return null;
  }

  // 좌표가 없으면 이름 완전 일치만 허용
  const exact = items.find((it) => it.title?.trim() === name.trim());
  if (exact) return exact;
  return null;
}

/** 콘텐츠 타입별 소개정보 정규화 */
function normalizeIntro(intro, typeId) {
  if (!intro) return {};
  const t = String(typeId);
  const pick = (o) => (o && String(o).trim() ? String(o).trim() : null);

  const base = {
    parking: null,
    useTime: null,
    restDate: null,
    useFee: null,
    infoCenter: null,
    menu: null,
    seat: null,
    packing: null,
    reservation: null,
    checkIn: null,
    checkOut: null,
    petAllowed: null,
    creditCard: null,
  };

  switch (t) {
    case "12": // 관광지
      return {
        ...base,
        useTime: pick(intro.usetime),
        restDate: pick(intro.restdate),
        parking: pick(intro.parking),
        infoCenter: pick(intro.infocenter),
        petAllowed: pick(intro.chkpet),
        creditCard: pick(intro.chkcreditcard),
      };
    case "14": // 문화시설
      return {
        ...base,
        useTime: pick(intro.usetimeculture),
        restDate: pick(intro.restdateculture),
        useFee: pick(intro.usefee),
        parking: pick(intro.parkingculture),
        infoCenter: pick(intro.infocenterculture),
      };
    case "32": // 숙박
      return {
        ...base,
        checkIn: pick(intro.checkintime),
        checkOut: pick(intro.checkouttime),
        parking: pick(intro.parkinglodging),
        reservation: pick(intro.reservationurl),
        infoCenter: pick(intro.infocenterlodging),
      };
    case "38": // 쇼핑
      return {
        ...base,
        useTime: pick(intro.opentime),
        restDate: pick(intro.restdateshopping),
        parking: pick(intro.parkingshopping),
        infoCenter: pick(intro.infocentershopping),
      };
    case "39": // 음식점
      return {
        ...base,
        menu: pick(intro.firstmenu) || pick(intro.treatmenu),
        useTime: pick(intro.opentimefood),
        restDate: pick(intro.restdatefood),
        parking: pick(intro.parkingfood),
        seat: pick(intro.seat),
        packing: pick(intro.packing),
        reservation: pick(intro.reservationfood),
        creditCard: pick(intro.chkcreditcardfood),
        infoCenter: pick(intro.infocenterfood),
      };
    default:
      return base;
  }
}

/**
 * 장소 하나에 대해 TourAPI 상세 정보 수집
 * @returns null 또는 { contentId, images, overview, homepage, intro }
 */
async function fetchTourDetail(name, lat, lng, key) {
  const content = await findContent(name, lat, lng, key);
  if (!content) return null;

  const contentId = content.contentid;
  const typeId = content.contenttypeid;

  // 공통정보 + 소개정보 + 이미지 병렬 조회
  const [commonBody, introBody, imageBody] = await Promise.all([
    callTour("detailCommon2", { contentId, contentTypeId: typeId }, key),
    callTour("detailIntro2", { contentId, contentTypeId: typeId }, key),
    callTour("detailImage2", { contentId, imageYN: "Y", numOfRows: 10 }, key),
  ]);

  const common = toArray(commonBody?.items)[0] || {};
  const intro = toArray(introBody?.items)[0] || {};
  const imgs = toArray(imageBody?.items);

  const images = [
    ...(content.firstimage ? [content.firstimage] : []),
    ...imgs.map((i) => i.originimgurl).filter(Boolean),
  ];
  // 중복 제거
  const uniqueImages = [...new Set(images)].slice(0, 8);

  const stripHtml = (s) =>
    (s || "").replace(/<[^>]*>/g, "").replace(/&[a-z]+;/g, " ").trim();

  const result = {
    contentId,
    contentTypeId: typeId,
    title: content.title,
    images: uniqueImages,
    thumbnail: content.firstimage || uniqueImages[0] || null,
    overview: stripHtml(common.overview) || null,
    homepage: stripHtml(common.homepage) || null,
    tel: common.tel || content.tel || null,
    ...normalizeIntro(intro, typeId),
  };

  console.log(
    `🏞 [TourAPI] 수집완료 ${result.title} | 사진 ${uniqueImages.length}장 | ` +
      `소개 ${result.overview ? "O" : "X"} | 시간 ${result.useTime ? "O" : "X"}`
  );

  return result;
}

const { UNIFIED_TO_TOUR_TYPE, TOUR_TYPE_TO_UNIFIED } = require("./categoryMap");

/**
 * 좌표 기반 관광정보 조회 (거리순, 대표이미지 있는 것 우선)
 * @param unified 통합 카테고리 (없으면 전체)
 */
async function findByLocation(lat, lng, key, { unified, radius = 500 } = {}) {
  const params = {
    mapX: lng,
    mapY: lat,
    radius: Math.min(radius, 20000),
    arrange: "S",          // S = 거리순 + 대표이미지 있는 것
    numOfRows: 20,
    pageNo: 1,
  };
  const typeId = unified ? UNIFIED_TO_TOUR_TYPE[unified] : null;
  if (typeId) params.contentTypeId = typeId;

  const body = await callTour("locationBasedList2", params, key);
  const items = toArray(body?.items);
  console.log(
    `🏞 [TourAPI] 위치조회 (${lat.toFixed(4)},${lng.toFixed(4)}) r=${radius} → ${items.length}건`
  );
  return items;
}

/**
 * 카카오로 찾은 장소에 TourAPI 정보를 매칭
 * 좌표 반경 내 + 이름 유사도로 판정
 */
async function matchByLocation(name, lat, lng, key, unified) {
  const items = await findByLocation(lat, lng, key, { unified, radius: 400 });
  if (items.length === 0) return null;

  const norm = (s) => (s || "").replace(/\s|·|\(|\)/g, "").toLowerCase();
  const target = norm(name);

  // 1) 이름 일치 우선
  let hit = items.find((it) => norm(it.title) === target);
  // 2) 포함 관계
  if (!hit) hit = items.find((it) => norm(it.title).includes(target) || target.includes(norm(it.title)));
  // 3) 100m 이내 최근접 (이름 달라도 같은 곳일 수 있음 — 보수적으로 제외)
  if (!hit) {
    console.log(`🏞 [TourAPI] 이름 불일치로 매칭 포기: "${name}"`);
    return null;
  }

  console.log(`🏞 [TourAPI] 매칭 ${hit.title} (${Math.round(Number(hit.dist))}m)`);
  return hit;
}

/** contentId로 상세 조회 (이미 검색된 항목에 사용) */
async function fetchDetailByContentId(contentId, typeId, key, listItem = {}) {
  const [commonBody, introBody, imageBody] = await Promise.all([
    callTour("detailCommon2", { contentId, contentTypeId: typeId }, key),
    callTour("detailIntro2", { contentId, contentTypeId: typeId }, key),
    callTour("detailImage2", { contentId, imageYN: "Y", numOfRows: 10 }, key),
  ]);

  const common = toArray(commonBody?.items)[0] || {};
  const intro = toArray(introBody?.items)[0] || {};
  const imgs = toArray(imageBody?.items);

  const images = [
    ...(listItem.firstimage ? [listItem.firstimage] : []),
    ...imgs.map((i) => i.originimgurl).filter(Boolean),
  ];
  const unique = [...new Set(images)].slice(0, 8);

  const strip = (s) =>
    (s || "").replace(/<[^>]*>/g, "").replace(/&[a-z]+;/g, " ").trim();

  return {
    contentId: String(contentId),
    contentTypeId: String(typeId),
    title: listItem.title || common.title,
    cat1: listItem.cat1 || common.cat1 || null,
    cat2: listItem.cat2 || common.cat2 || null,
    cat3: listItem.cat3 || common.cat3 || null,
    lcls1: listItem.lclsSystm1 || null,
    lcls2: listItem.lclsSystm2 || null,
    lcls3: listItem.lclsSystm3 || null,
    zipcode: listItem.zipcode || common.zipcode || null,
    thumbnail: listItem.firstimage || unique[0] || null,
    images: unique,
    overview: strip(common.overview) || null,
    homepage: strip(common.homepage) || null,
    tel: common.tel || listItem.tel || null,
    ...normalizeIntro(intro, typeId),
  };
}

module.exports = {
  fetchTourDetail,
  fetchDetailByContentId,     // ★ 추가
  findByLocation,
  matchByLocation,
  distanceM,
};