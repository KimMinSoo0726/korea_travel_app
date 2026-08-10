/**
 * AI 응답 텍스트에서 ```plan ... ``` 블록을 찾아 파싱한다.
 * 반환: { text, planJson }
 *  - text: plan 블록을 제거한 나머지 사람이 읽는 텍스트
 *  - planJson: 파싱된 객체 (없거나 실패하면 null)
 */
function parsePlanBlock(raw) {
  if (!raw) return { text: "", planJson: null };

  // ```plan ... ``` 또는 ```json ... ``` 모두 허용
  const fenceRegex = /```(?:plan|json)?\s*([\s\S]*?)```/i;
  const match = raw.match(fenceRegex);

  if (!match) {
    return { text: raw.trim(), planJson: null };
  }

  const jsonStr = match[1].trim();
  let planJson = null;

  try {
    const parsed = JSON.parse(jsonStr);
    // plan_options 형식인지 최소 검증
    if (parsed && (parsed.type === "plan_options" || parsed.plans || parsed.title)) {
      planJson = parsed;
    }
  } catch (e) {
    console.warn("plan JSON 파싱 실패:", e.message);
    planJson = null; // 파싱 실패 시 일반 텍스트로 처리
  }

  // 블록을 제거한 나머지 텍스트
  const text = raw.replace(fenceRegex, "").trim();

  return { text: text || "여행 플랜을 준비했어요. 아래에서 확인해보세요.", planJson };
}

module.exports = { parsePlanBlock };