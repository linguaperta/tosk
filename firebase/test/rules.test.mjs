// Firestore security rules: a user reads and writes only users/{own uid}/...,
// signed in with Google, with the documents the app writes (fixed shapes,
// size caps, a server-set `up`); reports for the developer (feedback/,
// crashes/ in the user's tree) can be created, read and deleted by their
// sender, never changed, and nobody else can see them.
// Run: cd firebase && npm install && npm test   (needs Java for the emulator)
import { after, before, beforeEach, test } from 'node:test';
import { readFileSync } from 'node:fs';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
} from 'firebase/firestore';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-tosk',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});
after(async () => env?.cleanup());
beforeEach(async () => env.clearFirestore());

/// A user signed in with Google (the only provider the rules accept for writes).
const user = (uid, provider = 'google.com') =>
  env.authenticatedContext(uid, { firebase: { sign_in_provider: provider } }).firestore();

// A copy of [data] without [keys] (Firestore refuses `undefined` values).
const without = (data, ...keys) => Object.fromEntries(Object.entries(data).filter(([k]) => !keys.includes(k)));

const batch = (extra = {}) => ({ v: 1, dev: 'phone', n: 1, events: '{"id":"e1"}\n', up: serverTimestamp(), ...extra });
const setting = (extra = {}) => ({ k: 'ui.theme_mode', v: 'dark', t: 1760000000000, dev: 'phone', up: serverTimestamp(), ...extra });
const batchId = '0123456789abcdef0123456789abcdef';

test('a user writes, reads and deletes their own batches and settings', async () => {
  const db = user('alice');
  await assertSucceeds(setDoc(doc(db, `users/alice/batches/${batchId}`), batch()));
  await assertSucceeds(setDoc(doc(db, `users/alice/batches/${batchId}`), batch({ n: 2 }))); // a retry overwrites
  await assertSucceeds(setDoc(doc(db, `users/alice/batches/${batchId}-2`), batch())); // a split batch
  await assertSucceeds(getDoc(doc(db, `users/alice/batches/${batchId}`)));
  await assertSucceeds(setDoc(doc(db, 'users/alice/settings/ui.theme_mode'), setting()));
  await assertSucceeds(setDoc(doc(db, 'users/alice/settings/goal.daily_xp'), setting({ k: 'goal.daily_xp', v: null })));
  await assertSucceeds(deleteDoc(doc(db, `users/alice/batches/${batchId}`)));
  await assertSucceeds(deleteDoc(doc(db, 'users/alice')));
});

test("nobody touches another user's data", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `users/alice/batches/${batchId}`), { ...batch(), up: Timestamp.now() });
  });
  const bob = user('bob');
  await assertFails(getDoc(doc(bob, `users/alice/batches/${batchId}`)));
  await assertFails(setDoc(doc(bob, 'users/alice/batches/b2'), batch()));
  await assertFails(deleteDoc(doc(bob, `users/alice/batches/${batchId}`)));
  const anon = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(anon, `users/alice/batches/${batchId}`)));
  await assertFails(setDoc(doc(anon, 'users/alice/batches/b2'), batch()));
});

test('writes need a Google sign-in', async () => {
  for (const provider of ['anonymous', 'password', 'custom']) {
    const db = user('alice', provider);
    await assertFails(setDoc(doc(db, `users/alice/batches/${batchId}`), batch()));
    await assertFails(setDoc(doc(db, 'users/alice/settings/ui.theme_mode'), setting()));
    await assertFails(setDoc(doc(db, `users/alice/feedback/${id}`), flag()));
    await assertFails(setDoc(doc(db, `users/alice/crashes/${id}`), crash()));
  }
});

test('sync documents must have the expected shape, caps and a server time', async () => {
  const db = user('alice');
  const b = (data, bid = batchId) => setDoc(doc(db, `users/alice/batches/${bid}`), data);
  const s = (data, key = 'ui.theme_mode') => setDoc(doc(db, `users/alice/settings/${key}`), data);
  await assertFails(b(batch({ up: Timestamp.fromMillis(0) })));
  await assertFails(b(batch({ extra: true })));
  await assertFails(b(batch({ events: 42 })));
  await assertFails(b(batch({ v: 2 })));
  await assertFails(b(batch({ n: 0 })));
  await assertFails(b(batch({ n: 401 })));
  await assertSucceeds(b(batch({ n: 400 })));
  await assertFails(b(batch({ dev: 'd'.repeat(65) })));
  await assertSucceeds(b(batch({ dev: 'd'.repeat(64) })));
  await assertFails(b(batch({ events: 'e'.repeat(250001) })));
  await assertSucceeds(b(batch({ events: 'e'.repeat(250000) })));
  await assertFails(b(without(batch(), 'dev')));
  await assertFails(b(batch(), 'x'.repeat(65)));
  await assertFails(b(batch(), 'bad.id'));
  await assertFails(s(setting({ t: 'yesterday' })));
  await assertFails(s(setting({ k: 'k'.repeat(101) })));
  await assertFails(s(setting({ v: 'v'.repeat(10001) })));
  await assertSucceeds(s(setting({ v: 'v'.repeat(10000) })));
  await assertFails(s(setting({ dev: 'd'.repeat(65) })));
  await assertFails(s(without(setting(), 'v')));
  await assertFails(s(setting(), 'k'.repeat(201)));
  await assertFails(s(setting(), 'bad key'));
  await assertSucceeds(s(setting(), 'chat.conversations%2Eit'));
  await assertFails(setDoc(doc(db, 'users/alice/other/x'), { a: 1 }));
  await assertFails(setDoc(doc(db, 'users/alice'), { a: 1 }));
});

// ------------------------------------------------------------------ reports

const flagJson = JSON.stringify({ format: 'tosk-flag/1', id: 'f1', course_id: 'it', exercise: { type: 'cloze' } });
const flag = (extra = {}) => ({
  v: 1, kind: 'flag', app: '0.7.6+19', platform: 'android', at: 1760000000000,
  text: 'Both should work?', flag: flagJson, course: 'it', up: serverTimestamp(), ...extra,
});
const general = (extra = {}) => ({
  v: 1, kind: 'general', app: '0.7.6+19', platform: 'web', at: 1760000000000,
  text: 'Lovely app, but the map is slow.', email: 'alice@example.com', up: serverTimestamp(), ...extra,
});
const crash = (extra = {}) => ({
  v: 1, app: '0.7.6+19', platform: 'android', device: 'Google Pixel 8', at: 1760000000000,
  report: 'Uncaught error: Bad state\n#0 main', up: serverTimestamp(), ...extra,
});
const id = '3f2b1c4e-0d6a-4b8e-9f00-1234567890ab';

test('a user sends flags, feedback and crash reports, and can read and delete their own', async () => {
  const db = user('alice');
  await assertSucceeds(setDoc(doc(db, `users/alice/feedback/${id}`), flag()));
  await assertSucceeds(setDoc(doc(db, 'users/alice/feedback/0a1b2c3d-general'), general()));
  await assertSucceeds(setDoc(doc(db, 'users/alice/feedback/0a1b2c3d-noemail'), without(general(), 'email')));
  await assertSucceeds(setDoc(doc(db, `users/alice/crashes/${id}`), crash()));
  await assertSucceeds(getDocs(collection(db, 'users/alice/feedback')));
  await assertSucceeds(getDoc(doc(db, `users/alice/crashes/${id}`)));
  // "Delete my cloud data" covers them.
  await assertSucceeds(deleteDoc(doc(db, `users/alice/feedback/${id}`)));
  await assertSucceeds(deleteDoc(doc(db, `users/alice/crashes/${id}`)));
});

test('reports can not be changed once sent, and nobody else sees them', async () => {
  const db = user('alice');
  await assertSucceeds(setDoc(doc(db, `users/alice/feedback/${id}`), flag()));
  await assertSucceeds(setDoc(doc(db, `users/alice/crashes/${id}`), crash()));
  await assertFails(updateDoc(doc(db, `users/alice/feedback/${id}`), { text: 'changed' }));
  await assertFails(setDoc(doc(db, `users/alice/feedback/${id}`), flag({ text: 'changed' })));
  await assertFails(setDoc(doc(db, `users/alice/crashes/${id}`), crash({ report: 'changed' })));
  const bob = user('bob');
  await assertFails(getDoc(doc(bob, `users/alice/feedback/${id}`)));
  await assertFails(getDocs(collection(bob, 'users/alice/crashes')));
  await assertFails(deleteDoc(doc(bob, `users/alice/feedback/${id}`)));
  await assertFails(setDoc(doc(bob, `users/alice/feedback/${id}`), flag()));
  await assertFails(setDoc(doc(bob, `users/alice/crashes/x${id}`), crash()));
  const anon = env.unauthenticatedContext().firestore();
  await assertFails(getDocs(collection(anon, 'users/alice/feedback')));
  await assertFails(setDoc(doc(anon, `users/alice/feedback/x${id}`), flag()));
});

test('an identical re-send (a retry after a lost acknowledgement) is allowed', async () => {
  const db = user('alice');
  await assertSucceeds(setDoc(doc(db, `users/alice/feedback/${id}`), flag()));
  await assertSucceeds(setDoc(doc(db, `users/alice/feedback/${id}`), flag()));
  await assertSucceeds(setDoc(doc(db, `users/alice/crashes/${id}`), crash()));
  await assertSucceeds(setDoc(doc(db, `users/alice/crashes/${id}`), crash()));
  // After the owner marked it seen, the app's re-send (a merge of its own
  // fields, as the REST updateMask does) still goes through and keeps the mark.
  await env.withSecurityRulesDisabled(async (ctx) => {
    await updateDoc(doc(ctx.firestore(), `users/alice/feedback/${id}`), { seen: Timestamp.now() });
  });
  await assertSucceeds(setDoc(doc(db, `users/alice/feedback/${id}`), flag(), { merge: true }));
  await assertFails(setDoc(doc(db, `users/alice/feedback/${id}`), flag({ text: 'changed' }), { merge: true }));
});

test('reports must have the expected shape, caps and a server time', async () => {
  const db = user('alice');
  const f = (data, docId = id) => setDoc(doc(db, `users/alice/feedback/${docId}`), data);
  const c = (data, docId = id) => setDoc(doc(db, `users/alice/crashes/${docId}`), data);
  await assertFails(f(flag({ up: Timestamp.fromMillis(0) })));
  await assertFails(f(flag({ extra: true })));
  await assertFails(f(flag({ uid: 'alice' })));
  await assertFails(f(flag({ seen: Timestamp.now() })));
  await assertFails(f(flag({ kind: 'spam' })));
  await assertFails(f(without(flag(), 'flag')));
  await assertFails(f(flag({ email: 'alice@example.com' })));
  await assertFails(f(general({ flag: flagJson })));
  await assertFails(f(flag({ text: 'x'.repeat(4001) })));
  await assertFails(f(flag({ flag: 'x'.repeat(60001) })));
  await assertFails(f(general({ email: 'x'.repeat(201) })));
  await assertFails(f(flag({ course: 'x'.repeat(65) })));
  await assertFails(f(flag({ app: 7 })));
  await assertFails(f(flag({ app: 'x'.repeat(41) })));
  await assertFails(f(flag({ platform: 'x'.repeat(21) })));
  await assertFails(f(flag({ at: 'now' })));
  await assertFails(f(flag({ v: 2 })));
  await assertFails(f(without(flag(), 'text')));
  await assertFails(f(flag(), 'short'));
  await assertFails(f(flag(), 'bad id with spaces'));
  await assertFails(f(flag(), 'x'.repeat(65)));
  await assertSucceeds(f(flag({ text: 'x'.repeat(4000), flag: 'x'.repeat(60000) })));
  await assertFails(c(crash({ report: 'x'.repeat(20001) })));
  await assertFails(c(crash({ report: '' })));
  await assertFails(c(crash({ device: 'x'.repeat(201) })));
  await assertFails(c(without(crash(), 'device')));
  await assertFails(c(crash({ email: 'alice@example.com' })));
  await assertFails(c(crash({ up: Timestamp.fromMillis(0) })));
  await assertSucceeds(c(crash({ report: 'x'.repeat(20000) })));
  await assertFails(setDoc(doc(db, 'feedback/x1234567'), general()));
  await assertFails(setDoc(doc(db, 'users/alice/reports/x1234567'), crash()));
});
