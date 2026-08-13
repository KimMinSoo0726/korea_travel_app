// 대략치 토큰 추정 (한글 기준). 실제값은 usageMetadata 로그로 보정.
const ROUGH_TOKENS = (s) => Math.ceil((s || "").length / 2);

// 지역 키워드 → regionCode 매핑 (지역 늘어나면 여기에 추가)
const REGION_TABLE = [
  { code: "hongdae", region: "홍대", kw: ["홍대", "홍익대"] },
  { code: "yeonnam", region: "연남동", kw: ["연남"] },
];

function resolveRegion(text) {
  const t = (text || "").toLowerCase();
  for (const r of REGION_TABLE) {
    if (r.kw.some((k) => t.includes(k.toLowerCase()))) return r;
  }
  return null;
}

// DB 문서 1건 → 프롬프트용 압축 한 줄
function projectLine(p) {
  const sub = p.category?.sub ? `/${p.category.sub}` : "";
  const one = p.oneLiner ? ` | ${p.oneLiner}` : "";
  const price = p.avgPrice ? ` · 평균 ${p.avgPrice}원` : "";
  const stay = p.stayMinutes ? ` · 약 ${p.stayMinutes}분` : "";
  const tags = p.category?.tags?.length
    ? ` · ${p.category.tags.slice(0, 3).join(",")}` : "";
  return `- ${p.name} | ${p.placeType || ""}${sub}${one}${price}${stay}${tags}`;
}

/**
 * @param col        c.regionPlaces
 * @param text       지역 판별용 텍스트 (유저 메시지 + 목적지)
 * @param tokenBudget 이 블록에 허용할 최대 추정 토큰
 * @returns null | { regionCode, regionName, block, total, included, estTokens }
 */
async function buildRegionBlock(col, text, { tokenBudget }) {
  const hit = resolveRegion(text);
  if (!hit) return null;

  const places = await col
    .find({ regionCode: hit.code })
    .sort({ popularity: -1 })
    .limit(500)
    .toArray();
  if (!places.length) return null;

  const header =
    `【${hit.region} 실제 검증 장소 DB — 최우선 활용】\n` +
    `아래는 실제 존재가 확인된 곳입니다. 일정에 장소를 넣을 땐 이 목록에서 먼저 고르고, ` +
    `여기에 없는 곳만 보조로 추천하세요. 목록에 있는 곳을 임의로 변형하지 마세요.\n`;

  let used = ROUGH_TOKENS(header);
  const lines = [];
  for (const p of places) {
    const line = projectLine(p);
    const cost = ROUGH_TOKENS(line + "\n");
    if (used + cost > tokenBudget) break;   // ★ 예산 초과 시 컷
    lines.push(line);
    used += cost;
  }

  return {
    regionCode: hit.code,
    regionName: hit.region,
    block: header + lines.join("\n") + "\n",
    total: places.length,
    included: lines.length,
    estTokens: used,
  };
}

module.exports = { buildRegionBlock, resolveRegion };