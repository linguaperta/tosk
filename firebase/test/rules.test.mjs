// Firestore security rules: a user reads and writes only users/{own uid}/...,
// with the documents the app writes and a server-set `up`.
// Run: cd firebase && npm install && npm test   (needs Java for the emulator)
import { after, before, beforeEach, test } from 'node:test';
import { readFileSync } from 'node:fs';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { deleteDoc, doc, getDoc, serverTimestamp, setDoc, Timestamp } from 'firebase/firestore';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-tosk',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});
after(async () => env?.cleanup());
beforeEach(async () => env.clearFirestore());

const batch = (extra = {}) => ({ v: 1, dev: 'phone', n: 1, events: '{"id":"e1"}\n', up: serverTimestamp(), ...extra });
const setting = (extra = {}) => ({ k: 'ui.theme_mode', v: 'dark', t: 1760000000000, dev: 'phone', up: serverTimestamp(), ...extra });

test('a user writes, reads and deletes their own batches and settings', async () => {
  const db = env.authenticatedContext('alice').firestore();
  await assertSucceeds(setDoc(doc(db, 'users/alice/batches/b1'), batch()));
  await assertSucceeds(setDoc(doc(db, 'users/alice/batches/b1'), batch({ n: 2 }))); // a retry overwrites
  await assertSucceeds(getDoc(doc(db, 'users/alice/batches/b1')));
  await assertSucceeds(setDoc(doc(db, 'users/alice/settings/ui.theme_mode'), setting()));
  await assertSucceeds(setDoc(doc(db, 'users/alice/settings/goal.daily_xp'), setting({ k: 'goal.daily_xp', v: null })));
  await assertSucceeds(deleteDoc(doc(db, 'users/alice/batches/b1')));
  await assertSucceeds(deleteDoc(doc(db, 'users/alice')));
});

test("nobody touches another user's data", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'users/alice/batches/b1'), { ...batch(), up: Timestamp.now() });
  });
  const bob = env.authenticatedContext('bob').firestore();
  await assertFails(getDoc(doc(bob, 'users/alice/batches/b1')));
  await assertFails(setDoc(doc(bob, 'users/alice/batches/b2'), batch()));
  await assertFails(deleteDoc(doc(bob, 'users/alice/batches/b1')));
  const anon = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(anon, 'users/alice/batches/b1')));
  await assertFails(setDoc(doc(anon, 'users/alice/batches/b2'), batch()));
});

test('documents must have the expected shape and a server time', async () => {
  const db = env.authenticatedContext('alice').firestore();
  await assertFails(setDoc(doc(db, 'users/alice/batches/b1'), batch({ up: Timestamp.fromMillis(0) })));
  await assertFails(setDoc(doc(db, 'users/alice/batches/b1'), batch({ extra: true })));
  await assertFails(setDoc(doc(db, 'users/alice/batches/b1'), batch({ events: 42 })));
  await assertFails(setDoc(doc(db, 'users/alice/settings/x'), setting({ t: 'yesterday' })));
  await assertFails(setDoc(doc(db, 'users/alice/other/x'), { a: 1 }));
  await assertFails(setDoc(doc(db, 'users/alice'), { a: 1 }));
});
