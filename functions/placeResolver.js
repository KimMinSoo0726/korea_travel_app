const { searchPoi, normalizePoi } = require("./tmapApi");
const { matchByLocation, fetchDetailByContentId } = require("./tourApi");
const { unifyFromTmap, unifyFromPlaceType } = require("./categoryMap");

const MAX_PLACES = 25;
const CONCURRENCY = 5;
const FRESH_DAYS = 90;
const MISS_DAYS = 7;

const norm = (s) =>
  (s || "").toLowerCase().replace(/[\s·,()[\]{}'"`~!@#$%^&*\-_=+./\\]/g, "");

const queryKey = (region, name) => `${norm(region)}|${norm(name)}`;

const isFresh = (d, days) =>
  d?.fetchedAt && Date.now() - new Date(d.fetchedAt).getTime() < days * 864e5;


// regionPlaces 문서 → applyToPlan이 먹는 place 형태로 변환
function regionDocToPlace(d) {
  return {
    _id: d._id,
    tmapPoiId: d.tmapPoiId ?? null,
    tourContentId: d.tourContentId ?? null,
    name: d.name,
    nameNorm: d.nameNorm || norm(d.name),
    category: {
      unified: d.category?.unified ?? null,
      tmapName: d.category?.sub ?? d.placeType ?? null,
    },
    address: {
      road: d.address?.road ?? null,
      jibun: d.address?.jibun ?? null,
      region: d.region ?? null,
    },
    location: d.location ?? null,
    contact: { phone: d.contact?.phone ?? null, homepage: d.contact?.homepage ?? null },
    media: { thumbnail: d.media?.thumbnail ?? null, images: d.media?.images ?? [] },
    detail: {
      overview: d.oneLiner ?? null,
      useTime: d.hours?.text ?? null,
      restDate: d.hours?.closedDay ?? null,
      parking: null, useFee: null,
      menu: d.signature?.length ? d.signature.join(", ") : null,
      checkIn: null, checkOut: null,
    },
    sources: ["db"],
    verifyStatus: "db",   // ★
  };
}

// 미스 대상들을 regionPlaces에서 이름으로 일괄 매칭
async function matchRegionDb(cols, targets) {
  const out = new Map();
  if (!cols.regionPlaces || !targets.length) return out;
  const normNames = [...new Set(targets.map((t) => norm(t.name)))];
  let docs = [];
  try {
    docs = await cols.regionPlaces.find({ nameNorm: { $in: normNames } }).toArray();
  } catch (e) {
    console.warn("지역DB 매칭 실패:", e.message);
    return out;
  }
  const byNorm = new Map(docs.map((d) => [d.nameNorm || norm(d.name), d]));
  for (const t of targets) {
    const d = byNorm.get(norm(t.name));
    if (d) out.set(t.name, regionDocToPlace(d));
  }
  if (out.size) console.log(`📗 [지역DB] ${out.size}건 매칭`);
  return out;
}

// ───────── 후보 점수 ─────────

function scorePoi(p, name, unified) {
  const t = norm(p.name);
  const n = norm(name);
  let s = 0;
  if (t === n) s += 100;
  else if (t.startsWith(n)) s += 60;
  else if (t.includes(n)) s += 40;
  else if (n.includes(t)) s += 25;
  else s -= 30;

  s -= Math.min(Math.abs(t.length - n.length) * 4, 40);

  if (unified) {
    const u = unifyFromTmap(p.bizUpper, p.bizMiddle, p.bizLower);
    if (u === unified) s += 35;
    else if (u === "OTHER") s -= 15;
  }
  return s;
}

// ───────── 장소 하나 해석 ─────────

async function resolvePlace({ name, placeType, region, hintLat, hintLng }, creds) {
  const unified = unifyFromPlaceType(placeType);

  let raws = await searchPoi(
    region ? `${region} ${name}` : name,
    creds.tmapKey,
    { lat: hintLat, lng: hintLng, radius: hintLat ? 10000 : undefined }
  );
  if (raws.length === 0) raws = await searchPoi(name, creds.tmapKey);
  if (raws.length === 0) return null;

  const pois = raws.map(normalizePoi).filter((p) => p.lat && p.lng);
  const scored = pois
    .map((p) => ({ p, s: scorePoi(p, name, unified) }))
    .sort((a, b) => b.s - a.s);

  console.log(`🎯 "${name}" (${placeType || "-"})`);
  scored.slice(0, 3).forEach((x, i) =>
    console.log(`   ${i + 1}. [${x.s}] ${x.p.name} | ${x.p.categoryName}`)
  );
  if (!scored.length || scored[0].s < 30) {
    console.warn("   ⚠️ 임계값 미달 → 포기");
    return null;
  }

  const t = scored[0].p;
  const uni = unifyFromTmap(t.bizUpper, t.bizMiddle, t.bizLower);

  // TourAPI 보강
  let tour = null;
  if (creds.tourKey) {
    try {
      const m = await matchByLocation(t.name, t.lat, t.lng, creds.tourKey, uni);
      if (m) {
        tour = await fetchDetailByContentId(
          m.contentid, m.contenttypeid, creds.tourKey, m
        );
      }
    } catch (e) {
      console.warn(`TourAPI 보강 실패: ${e.message}`);
    }
  }

  return {
    _id: `tmap:${t.poiId}`,
    tmapPoiId: t.poiId,
    tourContentId: tour?.contentId ?? null,

    name: t.name,
    nameNorm: norm(t.name),

    category: {
      unified: uni,
      tmapUpper: t.bizUpper, tmapMiddle: t.bizMiddle, tmapLower: t.bizLower,
      tmapName: t.categoryName,
      tourTypeId: tour?.contentTypeId ?? null,
      tourCat1: tour?.cat1 ?? null,
      tourCat2: tour?.cat2 ?? null,
      tourCat3: tour?.cat3 ?? null,
      lcls1: tour?.lcls1 ?? null,
      lcls2: tour?.lcls2 ?? null,
      lcls3: tour?.lcls3 ?? null,
    },

    address: {
      road: t.roadAddress,
      jibun: t.jibunAddress,
      zipcode: t.zipcode,
      region: t.region || region || null,
      sigungu: t.sigungu,
    },

    location: { type: "Point", coordinates: [t.lng, t.lat] },

    contact: {
      phone: t.tel || tour?.tel || null,
      homepage: tour?.homepage || null,
    },

    media: {
      thumbnail: tour?.thumbnail ?? null,
      images: tour?.images ?? [],
    },

    detail: {
      overview: tour?.overview ?? null,
      useTime: tour?.useTime ?? null,
      restDate: tour?.restDate ?? null,
      parking: tour?.parking ?? null,
      useFee: tour?.useFee ?? null,
      menu: tour?.menu ?? null,
      checkIn: tour?.checkIn ?? null,
      checkOut: tour?.checkOut ?? null,
    },

    verifyStatus: "confirmed",

    flags: { parking: t.parkFlag },
    sources: tour ? ["tmap", "tour"] : ["tmap"],
    fetchedAt: new Date().toISOString(),
  };
}

// ───────── 여러 장소 일괄 처리 (캐시 우선) ─────────

/**
 * @param targets [{ name, placeType, region }]
 * @param creds   { tmapKey, tourKey }
 * @param cols    collections() 결과
 * @returns Map<name, placeDoc|null>
 */
async function resolveMany(targets, creds, cols) {
  const results = new Map();
  const misses = [];

  // 1) 질의 캐시 조회
  const keys = targets.map((t) => queryKey(t.region, t.name));
  const qDocs = await cols.placeQueries.find({ _id: { $in: keys } }).toArray();
  const qMap = new Map(qDocs.map((d) => [d._id, d]));

  const placeIds = [];
  targets.forEach((t, i) => {
    const q = qMap.get(keys[i]);
    if (q && isFresh(q, q.resolved ? FRESH_DAYS : MISS_DAYS)) {
      if (q.placeId) placeIds.push(q.placeId);
      else results.set(t.name, null);
    } else {
      misses.push(t);
    }
  });

  // 2) 캐시된 장소 문서 로드
  if (placeIds.length) {
    const places = await cols.places.find({ _id: { $in: placeIds } }).toArray();
    const pMap = new Map(places.map((p) => [p._id, p]));
    targets.forEach((t, i) => {
      const q = qMap.get(keys[i]);
      if (q?.placeId && pMap.has(q.placeId)) {
        results.set(t.name, pMap.get(q.placeId));
      }
    });
  }

  const cacheCount = results.size;

  // 2.5) 지역 DB 우선 매칭 (req5·6)
  const dbHits = await matchRegionDb(cols, misses);
  const apiMisses = [];
  for (const t of misses) {
    if (dbHits.has(t.name)) results.set(t.name, dbHits.get(t.name));
    else apiMisses.push(t);
  }
  console.log(`📦 캐시 ${cacheCount}건 / 📗DB ${dbHits.size}건 / 🌐API ${apiMisses.length}건`);

  // 3) 나머지만 API 조회 (동시 실행 제한)
  const todo = apiMisses.slice(0, MAX_PLACES);
  if (todo.length < apiMisses.length) {
    console.log(`⚠️ 상한 초과로 ${apiMisses.length - todo.length}건 건너뜀`);
  }
  

  const fetched = [];
  let idx = 0;
  await Promise.all(
    Array.from({ length: CONCURRENCY }, async () => {
      while (idx < todo.length) {
        const t = todo[idx++];
        try {
          const p = await resolvePlace(t, creds);
          results.set(t.name, p);
          fetched.push({ target: t, place: p });
        } catch (e) {
          console.warn(`resolve 오류 ${t.name}: ${e.message}`);
          results.set(t.name, null);
          fetched.push({ target: t, place: null });
        }
      }
    })
  );

  // 4) 저장
  if (fetched.length) {
    const placeOps = [];
    const queryOps = [];
    const now = new Date().toISOString();

    for (const { target, place } of fetched) {
      const qk = queryKey(target.region, target.name);
      if (place) {
        placeOps.push({
          updateOne: {
            filter: { _id: place._id },
            update: { $set: place, $inc: { hitCount: 1 } },
            upsert: true,
          },
        });
        queryOps.push({
          updateOne: {
            filter: { _id: qk },
            update: {
              $set: {
                placeId: place._id, resolved: true,
                query: target.name, region: target.region, fetchedAt: now,
              },
              $inc: { hitCount: 1 },
            },
            upsert: true,
          },
        });
      } else {
        queryOps.push({
          updateOne: {
            filter: { _id: qk },
            update: {
              $set: {
                placeId: null, resolved: false,
                query: target.name, region: target.region, fetchedAt: now,
              },
              $inc: { hitCount: 1 },
            },
            upsert: true,
          },
        });
      }
    }

    if (placeOps.length) {
      await cols.places.bulkWrite(placeOps, { ordered: false });
    }
    if (queryOps.length) {
      await cols.placeQueries.bulkWrite(queryOps, { ordered: false });
    }
    console.log(`💾 장소 ${placeOps.length} / 질의 ${queryOps.length} 저장`);
  }

  // 5) 히트 카운트 증가 (캐시분)
  if (placeIds.length) {
    cols.places
      .updateMany({ _id: { $in: placeIds } }, { $inc: { hitCount: 1 } })
      .catch(() => {});
  }

  return results;
}

// ───────── plan JSON에 병합 ─────────

/**
 * @param planJson plan_options 형식
 * @param resolved resolveMany 결과 Map
 */
function applyToPlan(planJson, resolved) {
  const put = (obj, key) => {
    const p = resolved.get(obj[key]);
    if (!p) {
      if (!obj.verifyStatus) {
        obj.verifyStatus = obj.verified ? "confirmed" : "estimated";
      }
      return;
    }

    obj.placeId = p._id;
    obj.tmapPoiId = p.tmapPoiId;
    obj.tourContentId = p.tourContentId;

    obj.address = p.address.road || p.address.jibun || obj.address;
    if (p.location?.coordinates) {
      obj.lat = p.location.coordinates[1];
      obj.lng = p.location.coordinates[0];
    }

    obj.phone = p.contact.phone ?? obj.phone;
    obj.homepage = p.contact.homepage ?? obj.homepage;

    obj.category = p.category.tmapName || obj.category;
    obj.categoryCode = p.category.unified;

    obj.thumbnail = p.media.thumbnail;
    obj.images = p.media.images;

    obj.description = p.detail.overview || obj.description;
    obj.businessHours = p.detail.useTime ?? obj.businessHours;
    obj.closedDay = p.detail.restDate ?? obj.closedDay;
    obj.parking = p.detail.parking;
    obj.useFee = p.detail.useFee;
    obj.menu = p.detail.menu;
    obj.checkIn = p.detail.checkIn;
    obj.checkOut = p.detail.checkOut;

    obj.verified = true;
    obj.sources = p.sources;
    obj.verifyStatus =
      p.verifyStatus || (p.sources?.includes("db") ? "db" : "confirmed");  // ★
  };

  for (const plan of planJson.plans || []) {
    for (const day of plan.itinerary || []) {
      for (const it of day.items || []) put(it, "placeName");
    }
    for (const acc of plan.accommodations || []) put(acc, "name");
  }
  return planJson;
}

module.exports = { resolveMany, applyToPlan, resolvePlace, queryKey };