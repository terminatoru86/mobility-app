// MOBIlity – the phone's map areas (Firebase Cloud Function + Firestore).
//
// One document per PHONE (devices/{hash of the phone id}), not per account:
// uninstalling the app or making a new account does not give new free areas.
//  - at most 2 free areas for the life of the phone (freeEver never goes down)
//  - a free area can be moved once every 90 days (server time decides)
//  - paid areas: 30 days. TODO before launch: check the store receipt (Apple / Google) here.
//
// Deploy (after the Firebase project exists):
//   npm install -g firebase-tools && firebase login
//   firebase use --add            (pick the project)
//   cd server/functions && npm install && cd .. && firebase deploy --only functions
// Then put the function URL in lib/data/device_ledger.dart (kLedgerUrl).

const { onRequest } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.firestore();

const MAX_FREE = 2;
const MOVE_DAYS = 90;
const PASS_DAYS = 30;
const DAY = 24 * 3600 * 1000;

const key = (z) => `${z.c[0].toFixed(3)},${z.c[1].toFixed(3)}`;

exports.zoneLedger = onRequest({ cors: true }, async (req, res) => {
  if (req.method !== 'POST') return res.status(405).end();
  const { action, device, record } = req.body || {};
  if (typeof device !== 'string' || !/^[0-9a-f]{64}$/.test(device)) return res.status(400).end();
  const ref = db.collection('devices').doc(device);

  const out = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const old = snap.exists ? snap.data() : { zones: [], freeEver: 0, lastMove: null };
    if (action !== 'put' || !record) return old;

    const now = Date.now();
    const oldFree = old.zones.filter((z) => !z.p);
    const inFree = (record.zones || []).filter((z) => !z.p && Array.isArray(z.c));
    let freeEver = Math.max(old.freeEver || 0, oldFree.length);
    let lastMove = old.lastMove || null;
    const free = [...oldFree];
    // a move counts only when the rider pressed "I moved here" (the app then sends a newer lastMove)
    const wantsMove = typeof record.lastMove === 'number' && record.lastMove > (old.lastMove || 0);

    for (const z of inFree) {
      if (free.some((f) => key(f) === key(z))) continue; // already known
      if (freeEver < MAX_FREE && free.length < MAX_FREE) {
        free.push({ n: String(z.n || 'My area').slice(0, 60), c: z.c, p: false, a: now });
        freeEver += 1;
      } else if (wantsMove && free.length > 0 && (!lastMove || now - lastMove >= MOVE_DAYS * DAY)) {
        // "I moved here": replaces the free area the phone no longer sends
        const gone = free.findIndex((f) => !inFree.some((x) => key(x) === key(f)));
        if (gone >= 0) {
          free[gone] = { n: String(z.n || 'My area').slice(0, 60), c: z.c, p: false, a: now };
          lastMove = now;
        }
      }
      // otherwise refused: a third free area needs the payment
    }

    // paid passes: keep the ones the server knows, add new ones (TODO: verify the receipt)
    const paid = old.zones.filter((z) => z.p && z.u > now - 60 * DAY);
    for (const z of (record.zones || []).filter((x) => x.p && Array.isArray(x.c))) {
      if (paid.some((p) => key(p) === key(z) && Math.abs((p.a || 0) - (z.a || 0)) < DAY)) continue;
      paid.push({ n: String(z.n || 'Area').slice(0, 60), c: z.c, p: true, a: now, u: now + PASS_DAYS * DAY });
    }

    const rec = { zones: [...free, ...paid], freeEver, lastMove, updated: now };
    tx.set(ref, rec);
    return rec;
  });
  res.json({ zones: out.zones, freeEver: out.freeEver, lastMove: out.lastMove });
});
