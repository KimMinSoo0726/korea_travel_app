// 캐시 유효기간
const FRESH_DAYS_FOUND = 90;   // 찾은 장소: 90일
const FRESH_DAYS_MISS = 7;     // 못 찾은 장소: 7일 (재시도 여지)

/** 캐시 키 정규화: "부산|해운대해수욕장" */
function cacheKey(region, name) {
  const norm = (s) => (s || "").trim().toLowerCase().replace(/\s+/g, " ");
  return `${norm(region)}|${norm(name)}`;
}

function isFresh(doc) {
  if (!doc?.fetchedAt) return false;
  const days = doc.found ? FRESH_DAYS_FOUND : FRESH_DAYS_MISS;
  const age = Date.now() - new Date(doc.fetchedAt).getTime();
  return age < days * 24 * 60 * 60 * 1000;
}

/**
 * 캐시에서 한 번에 조회
 * @returns { hits: Map<key, data|null>, misses: string[] }
 */
async function readCache(placesCol, region, names) {
  const keys = names.map((n) => cacheKey(region, n));
  const docs = await placesCol.find({ _id: { $in: keys } }).toArray();
  const byKey = new Map(docs.map((d) => [d._id, d]));

  const hits = new Map();
  const misses = [];

  names.forEach((name, i) => {
    const doc = byKey.get(keys[i]);
    if (doc && isFresh(doc)) {
      hits.set(name, doc.found ? doc.data : null);
    } else {
      misses.push(name);
    }
  });

  return { hits, misses };
}

/** 조회 결과를 캐시에 일괄 저장 (upsert) */
async function writeCache(placesCol, region, results) {
  // results: [{ name, data|null }]
  if (!results.length) return;

  const now = new Date().toISOString();
  const ops = results.map(({ name, data }) => ({
    updateOne: {
      filter: { _id: cacheKey(region, name) },
      update: {
        $set: {
          region,
          name,
          found: !!data,
          data: data || null,
          fetchedAt: now,
        },
        $inc: { hitCount: 0 },
      },
      upsert: true,
    },
  }));

  await placesCol.bulkWrite(ops, { ordered: false });
}

/** 사용 횟수 카운트 (인기 장소 파악용, 선택) */
async function bumpHits(placesCol, region, names) {
  if (!names.length) return;
  const keys = names.map((n) => cacheKey(region, n));
  await placesCol.updateMany(
    { _id: { $in: keys } },
    { $inc: { hitCount: 1 } }
  );
}

module.exports = { cacheKey, readCache, writeCache, bumpHits };