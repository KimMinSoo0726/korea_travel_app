const UNIFIED = {
  RESTAURANT: "음식점", CAFE: "카페", ATTRACTION: "관광지",
  CULTURE: "문화시설", FESTIVAL: "축제/공연", COURSE: "여행코스",
  LEISURE: "레포츠", LODGING: "숙박", SHOPPING: "쇼핑",
  MARKET: "시장", OTHER: "기타",
};

/** 티맵 upperBizName/middleBizName → 통합 */
function unifyFromTmap(upper, middle, lower) {
  const s = `${upper || ""} ${middle || ""} ${lower || ""}`;
  if (/카페|커피|디저트|베이커리|제과/.test(s)) return "CAFE";
  if (/음식|한식|일식|중식|양식|분식|고기|해산물|뷔페|치킨|주점/.test(s)) return "RESTAURANT";
  if (/숙박|호텔|모텔|펜션|리조트|게스트/.test(s)) return "LODGING";
  if (/시장|재래시장/.test(s)) return "MARKET";
  if (/쇼핑|백화점|아울렛|마트/.test(s)) return "SHOPPING";
  if (/박물관|미술관|전시|공연|문화|극장|도서관/.test(s)) return "CULTURE";
  if (/관광|명소|공원|유원지|해수욕|사찰|유적|전망/.test(s)) return "ATTRACTION";
  if (/스포츠|레저|체육|캠핑|골프|스키/.test(s)) return "LEISURE";
  return "OTHER";
}

const TOUR_TYPE_TO_UNIFIED = {
  12: "ATTRACTION", 14: "CULTURE", 15: "FESTIVAL", 25: "COURSE",
  28: "LEISURE", 32: "LODGING", 38: "SHOPPING", 39: "RESTAURANT",
};

const UNIFIED_TO_TOUR_TYPE = {
  RESTAURANT: 39, CAFE: 39, ATTRACTION: 12, CULTURE: 14, FESTIVAL: 15,
  COURSE: 25, LEISURE: 28, LODGING: 32, SHOPPING: 38, MARKET: 38,
};

const PLACETYPE_TO_UNIFIED = {
  음식점: "RESTAURANT", 맛집: "RESTAURANT", 식당: "RESTAURANT",
  카페: "CAFE", 디저트: "CAFE",
  관광지: "ATTRACTION", 명소: "ATTRACTION", 공원: "ATTRACTION",
  문화재: "CULTURE", 미술관: "CULTURE", 박물관: "CULTURE", 문화시설: "CULTURE",
  축제: "FESTIVAL", 공연: "FESTIVAL",
  레포츠: "LEISURE", 액티비티: "LEISURE",
  숙소: "LODGING", 호텔: "LODGING", 펜션: "LODGING",
  쇼핑: "SHOPPING", 시장: "MARKET",
};

function unifyFromPlaceType(placeType) {
  if (!placeType) return null;
  for (const [k, v] of Object.entries(PLACETYPE_TO_UNIFIED)) {
    if (placeType.includes(k)) return v;
  }
  return null;
}

module.exports = {
  UNIFIED, unifyFromTmap, TOUR_TYPE_TO_UNIFIED,
  UNIFIED_TO_TOUR_TYPE, unifyFromPlaceType,
};