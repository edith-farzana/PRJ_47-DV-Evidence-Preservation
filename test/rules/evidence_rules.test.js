import { readFileSync } from 'node:fs';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { deleteDoc, doc, getDoc, setDoc, updateDoc } from 'firebase/firestore';
import { deleteObject, ref, uploadBytes } from 'firebase/storage';

/**
 * The headline deliverable of P5.
 *
 * The project claims a "secure read-only database". These tests are
 * what turn that from a sentence in a README into something checkable:
 * they prove the server refuses to update or delete an evidence
 * record, no matter who asks — including the account that created it.
 */

const PROJECT_ID = 'secure-evidence-rules-test';

const ALICE = 'alice-uid';
const MALLORY = 'mallory-uid';
const EVIDENCE_ID = 'evidence-1';

/** What the app actually uploads: hashes and a wrapped key, nothing else. */
const METADATA = {
  plaintextSha256: 'a'.repeat(64),
  ciphertextSha256: 'b'.repeat(64),
  wrappedDek: 'd3JhcHBlZC1kZWs=',
  nonce: 'bm9uY2U=',
  gcmTag: 'dGFn',
  capturedAt: '2026-09-21T10:00:00.000Z',
  fileSizeBytes: 4096,
  type: 'photo',
  encryptionAlgorithm: 'AES-256-GCM',
  keyVersion: 1,
};

const RECEIPT = {
  ciphertextSha256: 'b'.repeat(64),
  fileSizeBytes: 4096,
  backedUpAt: '2026-09-21T10:00:05.000Z',
};

let testEnv;

const rules = (name) =>
  readFileSync(new URL(`../../${name}`, import.meta.url), 'utf8');

const evidenceDoc = (db, uid = ALICE, id = EVIDENCE_ID) =>
  doc(db, 'users', uid, 'evidence', id);

const receiptDoc = (db, uid = ALICE, id = EVIDENCE_ID) =>
  doc(db, 'users', uid, 'backups', id);

const blobRef = (storage, uid = ALICE, id = EVIDENCE_ID) =>
  ref(storage, `users/${uid}/evidence/${id}.enc`);

/** Plants a record directly, bypassing rules, to test what happens next. */
const seedEvidence = (path = `users/${ALICE}/evidence/${EVIDENCE_ID}`) =>
  testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), path), METADATA);
  });

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: rules('firestore.rules'),
      host: '127.0.0.1',
      port: 8080,
    },
    storage: {
      rules: rules('storage.rules'),
      host: '127.0.0.1',
      port: 9199,
    },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.clearStorage();
});

after(async () => {
  await testEnv.cleanup();
});

describe('evidence records', () => {
  it('a signed-in user can create their own record', async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();

    await assertSucceeds(setDoc(evidenceDoc(db), METADATA));
  });

  it('a signed-in user can read their own record', async () => {
    await seedEvidence();

    const db = testEnv.authenticatedContext(ALICE).firestore();

    await assertSucceeds(getDoc(evidenceDoc(db)));
  });

  it('writing into another user\'s collection is denied', async () => {
    const db = testEnv.authenticatedContext(MALLORY).firestore();

    await assertFails(setDoc(evidenceDoc(db, ALICE), METADATA));
  });

  it('reading another user\'s record is denied', async () => {
    await seedEvidence();

    const db = testEnv.authenticatedContext(MALLORY).firestore();

    await assertFails(getDoc(evidenceDoc(db, ALICE)));
  });

  it('reading while signed out is denied', async () => {
    await seedEvidence();

    const db = testEnv.unauthenticatedContext().firestore();

    await assertFails(getDoc(evidenceDoc(db)));
  });

  // The two that matter most.

  it('UPDATING a record is denied, even for its owner', async () => {
    await seedEvidence();

    const db = testEnv.authenticatedContext(ALICE).firestore();

    await assertFails(
      updateDoc(evidenceDoc(db), { plaintextSha256: 'c'.repeat(64) }),
    );
  });

  it('DELETING a record is denied, even for its owner', async () => {
    await seedEvidence();

    const db = testEnv.authenticatedContext(ALICE).firestore();

    await assertFails(deleteDoc(evidenceDoc(db)));
  });

  it('overwriting an existing record with set() is denied', async () => {
    await seedEvidence();

    const db = testEnv.authenticatedContext(ALICE).firestore();

    await assertFails(setDoc(evidenceDoc(db), METADATA));
  });
});

describe('backup receipts', () => {
  it('the owner can create a receipt', async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();

    await assertSucceeds(setDoc(receiptDoc(db), RECEIPT));
  });

  it('updating a receipt is denied', async () => {
    await seedEvidence(`users/${ALICE}/backups/${EVIDENCE_ID}`);

    const db = testEnv.authenticatedContext(ALICE).firestore();

    await assertFails(updateDoc(receiptDoc(db), { fileSizeBytes: 1 }));
  });

  it('deleting a receipt is denied', async () => {
    await seedEvidence(`users/${ALICE}/backups/${EVIDENCE_ID}`);

    const db = testEnv.authenticatedContext(ALICE).firestore();

    await assertFails(deleteDoc(receiptDoc(db)));
  });
});

describe('encrypted blobs in storage', () => {
  const blob = new Uint8Array([1, 2, 3, 4]);

  // A fresh path per test. `clearStorage()` does not reliably empty the
  // emulator's bucket between tests, and because the rules forbid
  // overwriting, a leftover object from an earlier test makes the next
  // upload fail for the wrong reason.
  let attempt = 0;
  let id;

  beforeEach(() => {
    id = `${EVIDENCE_ID}-${++attempt}`;
  });

  it('the owner can upload their own blob', async () => {
    const storage = testEnv.authenticatedContext(ALICE).storage();

    await assertSucceeds(uploadBytes(blobRef(storage, ALICE, id), blob));
  });

  it('uploading into another user\'s space is denied', async () => {
    const storage = testEnv.authenticatedContext(MALLORY).storage();

    await assertFails(uploadBytes(blobRef(storage, ALICE, id), blob));
  });

  it('OVERWRITING an existing blob is denied', async () => {
    const storage = testEnv.authenticatedContext(ALICE).storage();

    await assertSucceeds(uploadBytes(blobRef(storage, ALICE, id), blob));
    await assertFails(
      uploadBytes(blobRef(storage, ALICE, id), new Uint8Array([9, 9, 9, 9])),
    );
  });

  it('DELETING a blob is denied', async () => {
    const storage = testEnv.authenticatedContext(ALICE).storage();

    await assertSucceeds(uploadBytes(blobRef(storage, ALICE, id), blob));
    await assertFails(deleteObject(blobRef(storage, ALICE, id)));
  });
});
