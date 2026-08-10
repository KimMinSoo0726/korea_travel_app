const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { GoogleGenAI } = require("@google/genai");
const { randomUUID } = require("crypto");

const { SYSTEM_INSTRUCTION } = require("./systemInstruction");
const { parsePlanBlock } = require("./planParser");
const { enrichPlanOptions } = require("./placeEnricher");
const { collections } = require("./db");

const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");
const NAVER_CLIENT_ID = defineSecret("NAVER_CLIENT_ID");
const NAVER_CLIENT_SECRET = defineSecret("NAVER_CLIENT_SECRET");
const NCP_KEY_ID = defineSecret("NCP_KEY_ID");
const NCP_KEY = defineSecret("NCP_KEY");
const MONGODB_URI = defineSecret("MONGODB_URI");
const TOUR_API_KEY = defineSecret("TOUR_API_KEY");
const TMAP_APP_KEY = defineSecret("TMAP_APP_KEY");
const { routeCar, routeWalk, routeTransit } = require("./tmapApi");

const QWEN_ENDPOINT = defineSecret("QWEN_ENDPOINT"); 
const QWEN_API_KEY = defineSecret("QWEN_API_KEY");   

const MODEL_NAME = process.env.GEMINI_MODEL || "gemini-3.1-flash-lite";

    

exports.chatWithGemini = onCall(
  {
    region: "asia-northeast3",
    secrets: [
      GEMINI_API_KEY, NAVER_CLIENT_ID, NAVER_CLIENT_SECRET,
      NCP_KEY_ID, NCP_KEY, MONGODB_URI,
    ],
    timeoutSeconds: 180,
    memory: "512MiB",
    invoker: "public", 
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    }
    const uid = request.auth.uid;
    const message = (request.data?.message ?? "").trim();
    let convId = request.data?.conversationId ?? null;

    if (!message) {
      throw new HttpsError("invalid-argument", "메시지가 비어 있습니다.");
    }

   const c = await collections(MONGODB_URI.value());
    const now = () => new Date().toISOString();

    // 1) 대화 생성 or 로드
    let conv = null;
    if (!convId) {
      // ★ 사용자 기본 취향을 새 대화에 상속
      const us = await c.userSettings.findOne({ _id: uid });
      const inheritedPrefs = us?.prefs ?? {};

      convId = randomUUID();
      const title = message.length > 20 ? message.slice(0, 20) + "…" : message;
      conv = {
        _id: convId, uid, title,
        settings: { prefs: inheritedPrefs, trip: {} },
        createdAt: now(), updatedAt: now(),
      };
      await c.conversations.insertOne(conv);
      console.log(`🆕 새 대화 — 취향 상속: ${JSON.stringify(inheritedPrefs)}`);
    } else {
      conv = await c.conversations.findOne({ _id: convId, uid });
    }

    // 2) 유저 메시지 저장
    const userMsg = {
      _id: randomUUID(), uid, conversationId: convId,
      role: "user", text: message, planJson: null, createdAt: now(),
    };
    await c.messages.insertOne(userMsg);

    // 3) 히스토리 로드 (최근 30개)
    const history = await c.messages
      .find({ conversationId: convId, uid })
      .sort({ createdAt: 1 })
      .limit(30)
      .toArray();

    try {
      const ai = new GoogleGenAI({ apiKey: GEMINI_API_KEY.value() });

         
      const today = new Date().toLocaleDateString('sv-SE', {
        timeZone: 'Asia/Seoul',
      }); // "2026-07-23" 형식
      const weekdays = ['일','월','화','수','목','금','토'];
      const dow = weekdays[
        new Date(new Date().toLocaleString('en-US', { timeZone: 'Asia/Seoul' })).getDay()
      ];


      const contents = history
        .filter((m) => m.text)
        .map((m) => ({
          role: m.role === "user" ? "user" : "model",
          parts: [{ text: m.text }],
        }));

      // 대화 설정 로드
      //const conv = await c.conversations.findOne({ _id: convId, uid });


      const st = conv?.settings || {};
      const p = st.prefs || {};
      const t = st.trip || {};

      const paceMap = { packed: "빡빡하게(하루 8개 이상)", normal: "보통(하루 5개 내외)", relaxed: "릴렉스(하루 3개 내외)" };
      const settingsBlock = [
        p.pace ? `- 여행 강도: ${paceMap[p.pace] || p.pace}` : null,
        p.interests?.length ? `- 관심사: ${p.interests.join(", ")}` : null,
        p.planningMode === "planned"
          ? "- 계획 방식: 계획적 — 단계마다 사용자에게 확인하며 진행"
          : p.planningMode === "auto"
          ? "- 계획 방식: 무계획 — 알아서 완성된 코스 제안"
          : null,
        t.destination ? `- 목적지: ${t.destination}` : null,
        t.origin ? `- 출발지: ${t.origin}` : null,
        t.startDate ? `- 출발일: ${t.startDate}${t.duration ? ` (${t.duration}일)` : ""}` : null,
        t.arrivalTime ? `- 도착 시각: ${t.arrivalTime}` : null,
        t.returnLocation ? `- 복귀: ${t.returnLocation}${t.returnDeadline ? ` (${t.returnDeadline}까지)` : ""}` : null,
        (t.adults || t.children)
          ? `- 인원: 성인 ${t.adults || 0}, 아동 ${t.children || 0}` : null,
        t.transport ? `- 교통편: ${t.transport}` : null,
        t.budget ? `- 예산: ${t.budget}` : null,
      ].filter(Boolean).join("\n");

      if (settingsBlock) {
        console.log("⚙️ 설정 적용:\n" + settingsBlock);
      }

      const response = await ai.models.generateContent({
        model: MODEL_NAME,
        contents,
        config: {
          systemInstruction:
            `【오늘 날짜: ${today} (${dow}요일), 한국 시간 기준】\n` +
            `사용자가 "다음 주", "이번 주말" 같이 말하면 이 날짜를 기준으로 계산하세요.\n` +
            `연도를 임의로 추측하지 말고 반드시 위 날짜를 기준으로 삼으세요.\n\n` +
            (settingsBlock
              ? `【사용자가 설정한 여행 조건 — 이미 아는 정보이므로 다시 묻지 마세요】\n${settingsBlock}\n\n`
              : "") +
            SYSTEM_INSTRUCTION,
          temperature: 0.7,
          maxOutputTokens: 32768,
        },
      });

      const rawText = response.text ?? ""; 

      const finishReason = response.candidates?.[0]?.finishReason;
      console.log("📏 응답 길이:", rawText.length, "종료사유:", finishReason);
      if (finishReason === "MAX_TOKENS") {
        console.warn("⚠️ 출력이 잘렸습니다. 플랜 수나 토큰 한도를 조정하세요.");
      }
      let { text, planJson } = parsePlanBlock(rawText);

      // 4) 장소 보정
      if (planJson) {
        try {
          planJson = await enrichPlanOptions(
            planJson,
            {
              clientId: NAVER_CLIENT_ID.value(),
              clientSecret: NAVER_CLIENT_SECRET.value(),
              keyId: NCP_KEY_ID.value(),
              key: NCP_KEY.value(),
              tourKey: TOUR_API_KEY.value(),
            },
            c.places            // ← 캐시 컬렉션 전달
          );
        } catch (e) {
          console.warn("장소 보정 건너뜀:", e.message);
        }
      }

      // ★ 플랜의 summary를 대화 설정에 자동 반영
      if (planJson?.plans?.[0]?.summary) {
        const sm = planJson.plans[0].summary;
        const p0 = planJson.plans[0];
        const autoTrip = {
          origin: sm.origin || "",
          destination: sm.destination || "",
          startDate: sm.startDate || "",
          duration: sm.duration || 0,
          arrivalTime: sm.arrivalTime || "",
          returnLocation: sm.returnLocation || "",
          returnDeadline: sm.returnDeadline || "",
          adults: sm.adults || 0,
          children: sm.children || 0,
          transport: p0.transport || "",
          budget: sm.budget || "",
        };
        const merged = { ...(conv?.settings || {}), trip: autoTrip };
        await c.conversations.updateOne(
          { _id: convId, uid },
          { $set: { settings: merged } }
        );
        console.log(`🧭 대화 여행정보 자동 갱신: ${autoTrip.destination} ${autoTrip.duration}일`);
      }

      // 5) AI 메시지 저장
      const aiMsg = {
        _id: randomUUID(), uid, conversationId: convId,
        role: "assistant",
          // ★ 추가
        text, planJson,
        enriched: false,
        createdAt: now(),
      };
      await c.messages.insertOne(aiMsg);
      await c.conversations.updateOne(
        { _id: convId, uid },
        { $set: { updatedAt: now() } }
      );

      // 6) 클라이언트로 반환 (대화 id + 두 메시지)
      return { conversationId: convId, userMessage: userMsg, aiMessage: aiMsg };
    } catch (err) {
      console.error("Gemini 호출 오류:", err);
      const errMsg = {
        _id: randomUUID(), uid, conversationId: convId,
        role: "assistant",
        text: "⚠️ 응답 생성 중 오류가 발생했습니다.",
        planJson: null, createdAt: now(),
      };
      await c.messages.insertOne(errMsg);
      return { conversationId: convId, userMessage: userMsg, aiMessage: errMsg };
    }
  }
);

const { routeKey, readRoute, writeRoute } = require("./routeCache");

exports.getRoute = onCall(
  {
    region: "asia-northeast3",
    secrets: [TMAP_APP_KEY, MONGODB_URI],
    timeoutSeconds: 180,
    invoker: "public",
  },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인 필요");

    const points = request.data?.points ?? [];
    const mode = request.data?.mode || "car";
    if (points.length < 2) return { path: [], mode };

    const c = await collections(MONGODB_URI.value());
    const key = routeKey(mode, points);

    // 1) 캐시
    const cached = await readRoute(c.routes, key);
    if (cached) {
      c.routes.updateOne({ _id: key }, { $inc: { hitCount: 1 } }).catch(() => {});
      console.log(`📦 [경로] 캐시 히트 ${key} (${cached.path?.length}점)`);
      return { ...cached, cached: true };
    }

    console.log(`🛣 [경로] mode=${mode} 지점 ${points.length}개 — API 조회`);
    const appKey = TMAP_APP_KEY.value();

    try {
      let r;
      if (mode === "walk" || mode === "bike") r = await routeWalk(points, appKey);
      else if (mode === "transit") r = await routeTransit(points, appKey);
      else r = await routeCar(points, appKey);

      if (!r.path || r.path.length === 0) {
        console.warn("⚠️ [경로] 실패 → 직선 폴백");
        return {
          path: points.map((p) => [p.lng, p.lat]),
          distance: 0, duration: 0, mode, straight: true,
        };
      }

      const doc = {
        mode,
        waypoints: points.map((p) => [p.lng, p.lat]),
        path: r.path,
        distance: r.distance,
        duration: r.duration,
        legs: r.legs ?? null,
        segments: r.segments ?? null,
        fare: r.fare ?? 0,
        transferCount: r.transferCount ?? 0,
        totalWalkTime: r.totalWalkTime ?? 0,
        totalWalkDistance: r.totalWalkDistance ?? 0,
        fallbackWalk: r.fallbackWalk ?? 0,
        transitUnavailable: r.transitUnavailable ?? false,
      };

      await writeRoute(c.routes, key, doc);
      console.log(
        `✅ [경로] ${r.path.length}점, ${Math.round(r.distance / 100) / 10}km, ` +
        `${Math.round(r.duration / 60000)}분 — 저장`
      );

      return { ...doc, cached: false };
    } catch (e) {
      console.error(`❌ [경로] ${e.message}`);
      return { path: [], mode };
    }
  }
);

const { onRequest } = require("firebase-functions/v2/https");

// 허용 호스트 (오픈 프록시 방지)
const IMAGE_HOSTS = new Set([
  "tong.visitkorea.or.kr",
  "cdn.visitkorea.or.kr",
]);

exports.imageProxy = onRequest(
  {
    region: "asia-northeast3",
    cors: true,
    invoker: "public",
    memory: "256MiB",
    timeoutSeconds: 30,
  },
  async (req, res) => {
    const raw = req.query.url;
    if (!raw || typeof raw !== "string") {
      res.status(400).send("url required");
      return;
    }

    let target;
    try {
      target = new URL(raw);
    } catch {
      res.status(400).send("invalid url");
      return;
    }

    if (!IMAGE_HOSTS.has(target.hostname)) {
      console.warn(`🚫 [이미지] 허용되지 않은 호스트: ${target.hostname}`);
      res.status(403).send("host not allowed");
      return;
    }

    try {
      const upstream = await fetch(target.toString());
      if (!upstream.ok) {
        res.status(upstream.status).send("upstream error");
        return;
      }

      const type = upstream.headers.get("content-type") || "image/jpeg";
      if (!type.startsWith("image/")) {
        res.status(415).send("not an image");
        return;
      }

      const buf = Buffer.from(await upstream.arrayBuffer());
      res.set("Content-Type", type);
      res.set("Cache-Control", "public, max-age=604800, immutable"); // 7일
      res.set("Access-Control-Allow-Origin", "*");
      res.send(buf);
    } catch (e) {
      console.error(`❌ [이미지] ${e.message}`);
      res.status(502).send("fetch failed");
    }
  }
);


exports.chatWithQwen = onCall(
  {
    region: "asia-northeast3",
    secrets: [QWEN_ENDPOINT, QWEN_API_KEY, MONGODB_URI],
    timeoutSeconds: 300,
    memory: "512MiB",
    invoker: "public",
  },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인 필요");

    const uid = request.auth.uid;
    const convId = request.data?.conversationId;
    const message = request.data?.message;
    if (!message) throw new HttpsError("invalid-argument", "message 필요");

    // Gemini와 동일한 대화 맥락 사용 (같은 대화의 히스토리)
    const c = await collections(MONGODB_URI.value());
    const history = convId
      ? await c.messages
          .find({ conversationId: convId, uid })
          .sort({ createdAt: 1 })
          .limit(20)
          .toArray()
      : [];

    // 오늘 날짜 주입 (Gemini와 동일)
    const today = new Date().toLocaleDateString("sv-SE", { timeZone: "Asia/Seoul" });
    const weekdays = ["일","월","화","수","목","금","토"];
    const dow = weekdays[
      new Date(new Date().toLocaleString("en-US", { timeZone: "Asia/Seoul" })).getDay()
    ];

    // OpenAI 호환 형식 (Qwen 서버가 vLLM/Ollama면 이 형식)
    const messages = [
      {
        role: "system",
        content:
          `【오늘 날짜: ${today} (${dow}요일), 한국 시간 기준】\n` +
          SYSTEM_INSTRUCTION,
      },
      ...history.map((m) => ({
        role: m.role === "assistant" ? "assistant" : "user",
        content: m.text || "",
      })),
      { role: "user", content: message },
    ];

    let res;
    try {
      res = await fetch(`${QWEN_ENDPOINT.value()}/v1/chat/completions`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(QWEN_API_KEY.value()
            ? { Authorization: `Bearer ${QWEN_API_KEY.value()}` }
            : {}),
        },
        body: JSON.stringify({
          model: "Qwen3.6-35B-A3B",              // 서버의 모델명에 맞게
          messages,
          temperature: 0.7,
          max_tokens: 32768,   //32768
          stream: false,  
        }),
      });
    } catch (e) {
      console.error(`❌ [Qwen] 네트워크: ${e.message}`);
      throw new HttpsError("unavailable", `Qwen 서버 연결 실패: ${e.message}`);
    }

    const text = await res.text();
    if (!res.ok) {
      console.error(`❌ [Qwen] HTTP ${res.status} — ${text.slice(0, 300)}`);
      throw new HttpsError("internal", `Qwen 오류 ${res.status}`);
    }

    let data;
    try {
      data = JSON.parse(text);
    } catch {
      throw new HttpsError("internal", "Qwen 응답 파싱 실패");
    }

    let raw = data.choices?.[0]?.message?.content ?? "";
    raw = raw.replace(/<think>[\s\S]*?<\/think>/g, "").trim();
    console.log(`🐇 [Qwen] 응답 ${raw.length}자`);

   const { text: parsedText, planJson } = parsePlanBlock(raw);

    // ★ Qwen 메시지 저장 (model: "qwen" 으로 구분)
    if (convId) {
      const c2 = await collections(MONGODB_URI.value());
      await c2.messages.insertOne({
        _id: randomUUID(),
        uid,
        conversationId: convId,
        role: "assistant",
        model: "qwen",              // ★ 구분자
        text: parsedText,
        planJson,
        enriched: false,            // Qwen은 보강 안 함
        createdAt: new Date().toISOString(),
      });
      console.log(`💾 [Qwen] 메시지 저장`);
    }

    return { text: parsedText, planJson };
  }
);


Object.assign(exports, require("./api"));

