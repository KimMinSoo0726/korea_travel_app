const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { randomUUID } = require("crypto");

const { collections, ensureIndexes } = require("./db");

const MONGODB_URI = defineSecret("MONGODB_URI");
const NAVER_CLIENT_ID = defineSecret("NAVER_CLIENT_ID");
const NAVER_CLIENT_SECRET = defineSecret("NAVER_CLIENT_SECRET");
const NCP_KEY_ID = defineSecret("NCP_KEY_ID");
const NCP_KEY = defineSecret("NCP_KEY");
const { enrichPlace } = require("./placeEnricher");
const { resolveMany, applyToPlan } = require("./placeResolver");

const TMAP_APP_KEY = defineSecret("TMAP_APP_KEY");
const TOUR_API_KEY = defineSecret("TOUR_API_KEY");

const opts = {
  region: "asia-northeast3",
  secrets: [MONGODB_URI],
  timeoutSeconds: 30,
  memory: "256MiB",
  invoker: "public",
};

/** 인증 확인 후 uid 반환 */
function requireUid(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  }
  return request.auth.uid;
}

// ───────── 대화 ─────────

exports.listConversations = onCall(opts, async (request) => {
  const uid = requireUid(request);
  const c = await collections(MONGODB_URI.value());
  const docs = await c.conversations
    .find({ uid })
    .sort({ updatedAt: -1 })
    .limit(100)
    .toArray();
  return { conversations: docs };
});

exports.createConversation = onCall(opts, async (request) => {
  const uid = requireUid(request);
  const title = request.data?.title || "새 대화";
  const c = await collections(MONGODB_URI.value());

  const now = new Date().toISOString();
  const doc = { _id: randomUUID(), uid, title, createdAt: now, updatedAt: now };
  await c.conversations.insertOne(doc);
  return { conversation: doc };
});

exports.deleteConversation = onCall(opts, async (request) => {
  const uid = requireUid(request);
  const convId = request.data?.conversationId;
  if (!convId) throw new HttpsError("invalid-argument", "conversationId 필요");

  const c = await collections(MONGODB_URI.value());
  // 본인 것인지 확인 후 삭제
  const res = await c.conversations.deleteOne({ _id: convId, uid });
  if (res.deletedCount > 0) {
    await c.messages.deleteMany({ conversationId: convId, uid });
  }
  return { deleted: res.deletedCount > 0 };
});

// ───────── 메시지 ─────────

exports.listMessages = onCall(opts, async (request) => {
  const uid = requireUid(request);
  const convId = request.data?.conversationId;
  const c = await collections(MONGODB_URI.value());
  const messages = await c.messages
    .find({ conversationId: convId, uid })
    .sort({ createdAt: 1 })
    .toArray();
  return { messages };   // 전체 반환 → model 포함됨
});

// ───────── 플랜 ─────────

exports.listPlans = onCall(opts, async (request) => {
  const uid = requireUid(request);
  const c = await collections(MONGODB_URI.value());
  const docs = await c.plans.find({ uid }).sort({ savedAt: -1 }).toArray();
  return { plans: docs };
});

exports.getPlan = onCall(opts, async (request) => {
  const uid = requireUid(request);
  const planId = request.data?.planId;
  const c = await collections(MONGODB_URI.value());
  const doc = await c.plans.findOne({ _id: planId, uid });
  return { plan: doc };
});

exports.savePlan = onCall(opts, async (request) => {
  const uid = requireUid(request);
  const plan = request.data?.plan;
  const conversationId = request.data?.conversationId ?? null;
  if (!plan) throw new HttpsError("invalid-argument", "plan 필요");

  const c = await collections(MONGODB_URI.value());
  const planId = randomUUID();
  const doc = {
    ...plan,
    _id: planId,
    uid,
    conversationId,
    savedAt: new Date().toISOString(),
  };
  await c.plans.insertOne(doc);

  // ★ 자동 일정 북마크
  if (conversationId) {
    const sm = plan.summary ?? {};
    await c.bookmarks.updateOne(
      { uid, conversationId, type: "itinerary", planId },
      {
        $setOnInsert: {
          _id: randomUUID(),
          uid,
          conversationId,
          type: "itinerary",
          messageId: request.data?.messageId ?? null,
          label: plan.title ?? plan.planLabel ?? "저장된 일정",
          note: "",
          itinerary: {
            planLabel: plan.planLabel ?? "",
            title: plan.title ?? "",
            dayCount: (plan.itinerary ?? []).length,
            destination: sm.destination ?? "",
            duration: sm.duration ?? 0,
          },
          fromSavedPlan: true,
          planId,
          createdAt: new Date().toISOString(),
        },
      },
      { upsert: true }
    );
    console.log(`🔖 저장 플랜 자동 북마크: ${plan.title}`);
  }

  return { plan: doc };
});


exports.updatePlan = onCall(opts, async (request) => {
  const uid = requireUid(request);
  const plan = request.data?.plan;
  const planId = plan?._id;
  if (!planId) throw new HttpsError("invalid-argument", "plan._id 필요");

  const c = await collections(MONGODB_URI.value());
  const { _id, uid: _u, ...updatable } = plan;
  await c.plans.updateOne({ _id: planId, uid }, { $set: updatable });
  return { updated: true };
});

exports.deletePlan = onCall(opts, async (request) => {
  const uid = requireUid(request);
  const planId = request.data?.planId;
  if (!planId) throw new HttpsError("invalid-argument", "planId 필요");

  const c = await collections(MONGODB_URI.value());
  await c.plans.deleteOne({ _id: planId, uid });
  console.log(`🗑 플랜 삭제: ${planId}`);

  // ★ 연결된 북마크는 남기되 "저장됨" 표시 해제
  const r = await c.bookmarks.updateMany(
    { uid, planId, fromSavedPlan: true },
    { $set: { fromSavedPlan: false, planId: null } }
  );
  if (r.modifiedCount > 0) {
    console.log(`🔖 북마크 ${r.modifiedCount}건 → 일반 북마크로 전환`);
  }

  return { ok: true };
});

// ───────── 최초 세팅용 ─────────

exports.setupIndexes = onCall(opts, async (request) => {
  requireUid(request);
  await ensureIndexes(MONGODB_URI.value());
  return { ok: true };
});


/** 대화 단위로 묶인 플랜 목록 */
exports.listPlanGroups = onCall(opts, async (request) => {
  const uid = requireUid(request);
  const c = await collections(MONGODB_URI.value());

  const plans = await c.plans.find({ uid }).sort({ savedAt: -1 }).toArray();
  if (plans.length === 0) return { groups: [] };

  // 관련 대화 정보 한 번에 조회
  const convIds = [...new Set(plans.map((p) => p.conversationId).filter(Boolean))];
  const convs = convIds.length
    ? await c.conversations.find({ _id: { $in: convIds }, uid }).toArray()
    : [];
  const convMap = new Map(convs.map((v) => [v._id, v]));

  // 그룹핑
  const groupMap = new Map();
  for (const p of plans) {
    const key = p.conversationId || "__none__";
    if (!groupMap.has(key)) {
      const conv = convMap.get(p.conversationId);
      groupMap.set(key, {
        conversationId: p.conversationId || null,
        conversationTitle: conv?.title || "대화 없음",
        conversationCreatedAt: conv?.createdAt || p.savedAt,
        plans: [],
      });
    }
    groupMap.get(key).plans.push(p);
  }

  const groups = [...groupMap.values()].sort((a, b) =>
    (b.conversationCreatedAt || "").localeCompare(a.conversationCreatedAt || "")
  );

  console.log(`📚 플랜 그룹 ${groups.length}개 / 플랜 ${plans.length}개`);
  return { groups };
});

// ───────── 사용자 기본 설정 ─────────

exports.getUserSettings = onCall(opts, async (request) => {
  const uid = requireUid(request);
  const c = await collections(MONGODB_URI.value());
  const doc = await c.userSettings.findOne({ _id: uid });
  return { prefs: doc?.prefs ?? null };
});

exports.saveUserSettings = onCall(opts, async (request) => {
  const uid = requireUid(request);
  const prefs = request.data?.prefs;
  if (!prefs) throw new HttpsError("invalid-argument", "prefs 필요");

  const c = await collections(MONGODB_URI.value());
  await c.userSettings.updateOne(
    { _id: uid },
    { $set: { prefs, updatedAt: new Date().toISOString() } },
    { upsert: true }
  );
  return { ok: true };
});

// ───────── 대화별 설정 ─────────

exports.getConversationSettings = onCall(opts, async (request) => {
  const uid = requireUid(request);
  const convId = request.data?.conversationId;
  const c = await collections(MONGODB_URI.value());

  if (!convId) {
    const u = await c.userSettings.findOne({ _id: uid });
    return { settings: { prefs: u?.prefs ?? {}, trip: {} } };
  }

  const conv = await c.conversations.findOne({ _id: convId, uid });
  if (conv?.settings) return { settings: conv.settings };

  // 없으면 사용자 기본값으로
  const u = await c.userSettings.findOne({ _id: uid });
  return { settings: { prefs: u?.prefs ?? {}, trip: {} } };
});

exports.saveConversationSettings = onCall(opts, async (request) => {
  const uid = requireUid(request);
  const convId = request.data?.conversationId;
  const settings = request.data?.settings;
  if (!convId || !settings) {
    throw new HttpsError("invalid-argument", "conversationId, settings 필요");
  }
  const c = await collections(MONGODB_URI.value());
  await c.conversations.updateOne(
    { _id: convId, uid },
    { $set: { settings, updatedAt: new Date().toISOString() } }
  );
  return { ok: true };
});


exports.enrichPlanMessage = onCall(
  {
    region: "asia-northeast3",
    secrets: [MONGODB_URI, TMAP_APP_KEY, TOUR_API_KEY],
    timeoutSeconds: 300,
    memory: "512MiB",
    invoker: "public",
  },
  async (request) => {
    const uid = requireUid(request);
    const messageId = request.data?.messageId;
    if (!messageId) throw new HttpsError("invalid-argument", "messageId 필요");

    const c = await collections(MONGODB_URI.value());
    const msg = await c.messages.findOne({ _id: messageId, uid });

    if (!msg?.planJson) return { planJson: null, enriched: false };
    if (msg.enriched) {
      return { planJson: msg.planJson, enriched: true, cached: true };
    }

    // 대상 수집
    const region = msg.planJson.plans?.[0]?.summary?.destination || "";
    const targets = [];
    const seen = new Set();

    for (const plan of msg.planJson.plans || []) {
      for (const day of plan.itinerary || []) {
        for (const it of day.items || []) {
          if (it.placeName && !seen.has(it.placeName)) {
            seen.add(it.placeName);
            targets.push({
              name: it.placeName,
              placeType: it.placeType || it.category,
              region,
            });
          }
        }
      }
      for (const acc of plan.accommodations || []) {
        if (acc.name && !seen.has(acc.name)) {
          seen.add(acc.name);
          targets.push({ name: acc.name, placeType: "숙소", region });
        }
      }
    }

    console.log(`🔄 [보강] ${messageId} 대상 ${targets.length}건`);
    const started = Date.now();

    const resolved = await resolveMany(
      targets,
      {
        tmapKey: TMAP_APP_KEY.value(),
        tourKey: TOUR_API_KEY.value(),
      },
      c
    );

    const enriched = applyToPlan(msg.planJson, resolved);
    const matched = [...resolved.values()].filter(Boolean).length;

    await c.messages.updateOne(
      { _id: messageId, uid },
      { $set: { planJson: enriched, enriched: true } }
    );

    console.log(
      `✅ [보강] ${matched}/${targets.length}건 매칭 (${Date.now() - started}ms)`
    );

    return {
      planJson: enriched,
      enriched: true,
      matched,
      total: targets.length,
    };
  }
);


exports.listBookmarks = onCall(opts, async (request) => {
  const uid = requireUid(request);
  const conversationId = request.data?.conversationId;
  if (!conversationId) throw new HttpsError("invalid-argument", "conversationId 필요");

  const c = await collections(MONGODB_URI.value());
  const items = await c.bookmarks
    .find({ uid, conversationId })
    .sort({ createdAt: -1 })
    .toArray();

  console.log(`🔖 북마크 ${items.length}건 (대화 ${conversationId})`);
  return { bookmarks: items };
});

exports.addBookmark = onCall(opts, async (request) => {
  const uid = requireUid(request);
  const d = request.data ?? {};
  if (!d.conversationId || !d.type) {
    throw new HttpsError("invalid-argument", "conversationId, type 필요");
  }

  const c = await collections(MONGODB_URI.value());

  // 중복 방지 (같은 대화·타입·라벨)
  const dupFilter = {
    uid,
    conversationId: d.conversationId,
    type: d.type,
    label: d.label,
  };
  if (d.type === "place" && d.place?.placeId) {
    dupFilter["place.placeId"] = d.place.placeId;
  }
  if (d.type === "itinerary" && d.planId) {
    dupFilter.planId = d.planId;
  }
  const exist = await c.bookmarks.findOne(dupFilter);
  if (exist) {
    return { bookmark: exist, duplicated: true };
  }

  const doc = {
    _id: randomUUID(),
    uid,
    conversationId: d.conversationId,
    type: d.type,                    // place | itinerary
    messageId: d.messageId ?? null,
    label: d.label ?? "",
    note: d.note ?? "",
    place: d.type === "place" ? d.place ?? null : null,
    itinerary: d.type === "itinerary" ? d.itinerary ?? null : null,
    fromSavedPlan: d.fromSavedPlan === true,
    planId: d.planId ?? null,
    createdAt: new Date().toISOString(),
  };
  await c.bookmarks.insertOne(doc);
  console.log(`🔖 북마크 추가 [${doc.type}] ${doc.label}`);
  return { bookmark: doc, duplicated: false };
});

exports.updateBookmark = onCall(opts, async (request) => {
  const uid = requireUid(request);
  const { bookmarkId, note } = request.data ?? {};
  if (!bookmarkId) throw new HttpsError("invalid-argument", "bookmarkId 필요");

  const c = await collections(MONGODB_URI.value());
  await c.bookmarks.updateOne(
    { _id: bookmarkId, uid },
    { $set: { note: note ?? "" } }
  );
  return { ok: true };
});

exports.deleteBookmark = onCall(opts, async (request) => {
  const uid = requireUid(request);
  const bookmarkId = request.data?.bookmarkId;
  if (!bookmarkId) throw new HttpsError("invalid-argument", "bookmarkId 필요");

  const c = await collections(MONGODB_URI.value());
  await c.bookmarks.deleteOne({ _id: bookmarkId, uid });
  return { ok: true };
});

