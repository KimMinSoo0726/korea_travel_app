const { MongoClient } = require("mongodb");

let clientPromise = null;

/** 연결 싱글턴 — 인스턴스가 살아있는 동안 재사용 */
function getDb(uri) {
  if (!clientPromise) {
    const client = new MongoClient(uri, {
      maxPoolSize: 10,
      minPoolSize: 0,
      serverSelectionTimeoutMS: 8000,
      retryWrites: true,
    });
    clientPromise = client.connect().then((c) => c.db("koreatravel"));
  }
  return clientPromise;
}
async function collections(uri) {
  const db = await getDb(uri);
  return {
    conversations: db.collection("conversations"),
    messages: db.collection("messages"),
    plans: db.collection("plans"),
    places: db.collection("places"),
    placeQueries: db.collection("placeQueries"),
    userSettings: db.collection("userSettings"),
    routes: db.collection("routes"),
    bookmarks: db.collection("bookmarks"),
    regionPlaces: db.collection("regionPlaces"), 
  };
}

async function ensureIndexes(uri) {
  const c = await collections(uri);
  await Promise.all([
    c.conversations.createIndex({ uid: 1, updatedAt: -1 }),
    c.messages.createIndex({ conversationId: 1, createdAt: 1 }),
    c.plans.createIndex({ uid: 1, savedAt: -1 }),
    // places
     c.places.createIndex({ tmapPoiId: 1 }, { sparse: true }),
    c.places.createIndex({ tourContentId: 1 }, { sparse: true }),
    c.places.createIndex({ nameNorm: 1, "address.region": 1 }),
    c.places.createIndex({ location: "2dsphere" }),
    c.places.createIndex({ "category.unified": 1 }),
    c.placeQueries.createIndex({ fetchedAt: -1 }),
    c.routes.createIndex({ fetchedAt: -1 }),
    c.routes.createIndex({ mode: 1 }),    
    c.bookmarks.createIndex({ uid: 1, conversationId: 1, createdAt: -1 }),
    c.bookmarks.createIndex({ conversationId: 1, type: 1 }),
    c.bookmarks.createIndex({ planId: 1 }, { sparse: true }),
    c.regionPlaces.createIndex({ regionCode: 1, "category.unified": 1 }),
    c.regionPlaces.createIndex({ regionCode: 1, popularity: -1 }),
    c.regionPlaces.createIndex({ location: "2dsphere" }),
    c.regionPlaces.createIndex({ nameNorm: 1 }),
  ]);
}

module.exports = { getDb, collections, ensureIndexes };