const crypto = require("crypto");

const FRESH_DAYS = 30;

/** 좌표 시퀀스 + 모드 → 캐시 키 (순서가 바뀌면 키도 바뀜) */
function routeKey(mode, points) {
  const coords = points
    .map((p) => `${p.lng.toFixed(5)},${p.lat.toFixed(5)}`)
    .join("|");
  const hash = crypto.createHash("sha1").update(coords).digest("hex").slice(0, 16);
  return `${mode}:${hash}`;
}

async function readRoute(col, key) {
  const doc = await col.findOne({ _id: key });
  if (!doc) return null;
  const age = Date.now() - new Date(doc.fetchedAt).getTime();
  if (age > FRESH_DAYS * 864e5) return null;
  return doc;
}

async function writeRoute(col, key, data) {
  await col.updateOne(
    { _id: key },
    {
      $set: { ...data, _id: key, fetchedAt: new Date().toISOString() },
      $inc: { hitCount: 0 },
    },
    { upsert: true }
  );
}

module.exports = { routeKey, readRoute, writeRoute };