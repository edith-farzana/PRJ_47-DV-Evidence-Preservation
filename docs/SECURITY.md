# Security Design

**Project:** Secure Evidence — domestic violence evidence preservation
**Status of this document:** design specification. Sections are marked with their implementation status.
**Last updated:** 2026-09-23

> **Implementation status legend**
> 🔴 **Not built** — specified here, not yet in code
> 🟡 **Partial** — some of it exists
> 🟢 **Built** — implemented and covered by tests
>
> As of 2026-09-21 the crypto core (P1), key & PIN management (P2), encrypted on-device storage (P3) and the safety fixes (P4) are built and tested, as are evidence viewing and on-demand integrity verification (brought forward from P7). The backend (P5) is **written but not yet verified**: the rules and their tests exist, and nothing has been run against a real Firebase project. The audit log (P6) and court export (P7) are not built. See `DEVELOPMENT_CHECKLIST.md` for the build order. This document describes the target design so that implementation has something to be checked against — it is **not** a description of the current app.

---

## 1. Threat model

Security design is meaningless without saying who we are defending against. This app has an unusual threat model: **the attacker is likely to have physical access to the device, know the victim personally, and may know their habits and passwords.**

### Adversaries we defend against

| Adversary | Capability | Our defence |
|---|---|---|
| **A1 — Abuser with physical access to an unlocked phone** | Can browse apps, gallery, files | Decoy calculator; evidence never enters the gallery; no app icon that reveals purpose |
| **A2 — Abuser who suspects and searches the phone** | Opens apps, looks at storage via a file manager | PIN gate behind a hidden unlock sequence; all evidence encrypted at rest; screenshots and recents-preview blocked |
| **A3 — Abuser who coerces the victim to unlock** | Demands the PIN under threat | Duress PIN opening a decoy vault (P9, not built) |
| **A4 — Abuser who obtains the device and dumps storage** | ADB backup, root, forensic tools | AES-256-GCM at rest; keys in Android Keystore, unwrapped only by PIN |
| **A5 — Someone deleting evidence to destroy the case** | Has the phone, wants evidence gone | **Partial.** The immutable Firestore record proves the evidence existed and carries its hash, so deletion is always *detectable*. The media itself only survives if the user opted that item into cloud backup — see §3.3 |
| **A6 — Curious or compromised backend operator** | Can read the database and object store | Client-side encryption: the server only ever holds ciphertext and hashes. We cannot read user evidence, and neither can anyone who breaches us |
| **A7 — Someone altering evidence to weaken it in court** | Modifies a file or a record | SHA-256 of plaintext bound into the ciphertext as AAD; hash-chained audit log |

### Adversaries we explicitly do NOT defend against

Stating these honestly is part of the design, not an admission of failure.

- **A state-level or forensic-grade attacker** with the device unlocked and the app open. In-memory keys are extractable at that point.
- **A compromised or rooted device with an active keylogger.** If the OS is owned, the PIN is captured as it is typed and everything follows.
- **Malicious hardware / evil-maid attacks** on the device firmware.
- **Coercion beyond the duress PIN.** If the victim is forced to reveal the real PIN, the evidence is accessible. Technology has limits here.
- **Traffic analysis.** An observer on the network can see that the app talks to Firebase, even though they cannot read what is sent. Presence of the app is itself a signal.

---

## 2. Cryptographic design

### 2.1 Algorithms 🟡

| Purpose | Algorithm | Parameters |
|---|---|---|
| Bulk file encryption | **AES-256-GCM** | 256-bit key, 96-bit random nonce per file, 128-bit tag |
| Key wrapping | **AES-256-GCM** | 256-bit KEK, fresh nonce per wrap |
| Key derivation from PIN | **PBKDF2-HMAC-SHA256** | ≥150,000 iterations, 128-bit random salt (Argon2id preferred if the dependency allows) |
| Integrity hashing | **SHA-256** | Streamed over the file, never fully buffered |
| Audit chain | **SHA-256** | Each entry hashes the previous entry |
| Randomness | Platform CSPRNG | via `package:cryptography` `SecureRandom` |

**Why AES-GCM and not AES-CBC:** GCM is authenticated encryption. It detects tampering as part of decryption — a modified ciphertext fails to decrypt rather than producing plausible-looking garbage. For an evidence app, silently returning corrupted data would be worse than failing.

**Why a nonce per file, never reused:** GCM catastrophically loses confidentiality if a nonce is reused under the same key. Each file gets both a fresh key and a fresh nonce, so this cannot happen even by accident.

### 2.2 Key hierarchy (envelope encryption) 🟢

```
  User PIN  +  salt (random, 128-bit, stored in plain)
       │
       │  PBKDF2-HMAC-SHA256, ≥150,000 iterations
       ▼
  PIN-derived key (256-bit)  ── never stored, exists only during unlock
       │
       │  AES-256-GCM unwrap
       ▼
  Master Key / KEK (256-bit)  ── stored WRAPPED in flutter_secure_storage
       │                          (Android Keystore-backed)
       │                          in memory only while unlocked
       │
       │  AES-256-GCM unwrap, once per file
       ▼
  DEK (256-bit, unique per evidence file)
       │
       │  AES-256-GCM, AAD = SHA-256(plaintext)
       ▼
  Encrypted evidence blob  <uuid>.enc
```

**Why three levels instead of encrypting files directly with a PIN-derived key:**

1. **Changing the PIN re-wraps one 256-bit key, not gigabytes of video.** A PIN change is instant regardless of how much evidence is stored.
2. **Per-file DEKs limit blast radius.** Compromising one DEK exposes one file.
3. **The master key never leaves the device**, so the backend is cryptographically unable to read evidence.

**What is stored where:**

| Item | Location | Protected how |
|---|---|---|
| PIN | **Nowhere** | Never stored, in any form |
| PBKDF2 salt | `flutter_secure_storage` | Plain — a salt is not a secret |
| Master key | `flutter_secure_storage` | Wrapped by the PIN-derived key |
| DEK (per file) | Evidence metadata | Wrapped by the master key |
| Nonce, GCM tag | Evidence metadata | Plain — neither is secret |
| SHA-256 hashes | Evidence metadata + Firestore | Plain — used for verification |
| Evidence blob | Local `<uuid>.enc` + Firebase Storage | AES-256-GCM |

**Implementation:** `lib/services/crypto/key_manager.dart`. The salt, iteration count and wrapped master key are stored as **one** record (`km.v1.vault`), written in a single call, so a crash can never leave a salt that doesn't match its wrapped key. The wrap uses a fixed AAD label (`secure-evidence/master-key/v1`). PBKDF2 runs in a background isolate.

#### The Keystore layer: why a 4-digit PIN is acceptable

A 4-digit PIN has only 10,000 values. PBKDF2 makes each guess slower, but 10,000 slow guesses is still minutes of work for anyone holding the wrapped key. The defence is that **nobody holds it off the device**:

- `flutter_secure_storage` encrypts every stored value with an AES key that is itself wrapped by a **non-exportable RSA key in the Android Keystore**. The PIN-wrapped master key is therefore wrapped twice, and the outer layer can only be removed by this phone's Keystore.
- Backups are disabled (`allowBackup="false"`, and `data_extraction_rules.xml` excludes everything from cloud backup and device-to-device transfer), so the record never leaves the phone that way either.
- Guesses therefore have to go through the app on the phone, where the lockout in §4.2 applies.

**The limit, stated plainly:** this defeats an attacker with a **copy** of the storage (backup, forensic image of the app's files, a different phone). It does **not** defeat an attacker with **root on the live phone**. They can ask the Keystore to remove the outer layer, then try all 10,000 PINs offline, and they can reset the lockout counter. That is the "rooted device" case in §1, which we already list as out of scope. Stronger protection needs a hardware-enforced attempt counter (as the Android lock screen uses), which the platform does not offer to apps.

### 2.3 The AAD binding 🟢

The plaintext SHA-256 is passed as **Additional Authenticated Data** to AES-GCM. It is not encrypted, but it is authenticated: decryption fails if the hash recorded in metadata does not match the hash that was bound in at encryption time.

This closes an otherwise real attack: without it, someone could swap the stored hash to match a substituted file, and verification would pass. With AAD binding, ciphertext and hash are cryptographically welded together — you cannot alter one without invalidating the other.

### 2.4 Integrity verification 🟢

Two hashes are recorded per item:

- **`plaintextSha256`** — the evidentiary hash. Computed at capture, before encryption. This is what proves the file has not changed since it was captured, and what appears in a court export.
- **`ciphertextSha256`** — transport integrity. Detects corruption during upload or storage, without needing to decrypt.

Verification re-decrypts, re-hashes the plaintext, and compares to `plaintextSha256`.

---

## 3. Storage model

### 3.1 On-device 🟢

```
<app documents>/
  evidence/
    <uuid>.enc        ← AES-256-GCM encrypted blob (no extension)
    ...
    index.enc         ← AES-256-GCM encrypted list of evidence records
```

Implementation: `lib/services/storage/evidence_storage.dart`, `evidence_index.dart`.

- **No plaintext evidence is ever written to the evidence directory.** Blob names carry no file extension, and original filenames exist only inside the encrypted index.
- **Capture order** (the last step can't be undone, so everything before it must succeed): encrypt → decrypt again and compare SHA-256 → record in the index → overwrite the source with zeros and delete it. If any of the first three fail, the source is kept and the partial blob is removed.
- **The index** is encrypted under a key derived from the master key with HKDF-SHA256 (`info: evidence-index/v1`), so it never shares a key with any evidence file. It is replaced atomically (write temp, rename).
- **Rollback detection.** GCM catches any edit to `index.enc`, but not someone putting back an **older, genuine** copy to hide evidence captured since. So a seal, the item count plus the SHA-256 of the current `index.enc`, is kept in Keystore-backed secure storage, and every load checks the file against it. A crash mid-write is handled: the seal records the pending hash before the rename, so either file state still loads.
- **Fails loudly.** An index that is missing, altered, rolled back or undecryptable raises `EvidenceIndexCorruptedException`, and the vault shows a warning. It never shows "No evidence yet", which would tell a survivor their evidence is gone when the files are still there.
- **Append-only by construction:** `EvidenceStorage` deliberately exposes no `deleteEvidence()` or `updateEvidence()`.

> **Viewing** decrypts into a preview directory inside the cache, destroys the copy when the screen closes, and sweeps anything a crash left behind at the next launch. The source overwrite is best-effort; see §5 item 7.

### 3.2 Backend — Firebase 🟡

```
Firestore:  /users/{uid}/evidence/{evidenceId}    ← metadata + wrapped key, ALWAYS
            /users/{uid}/backups/{evidenceId}     ← receipt, only if backed up
            /users/{uid}/audit/{eventId}          ← hash-chained audit log

Storage:    /users/{uid}/evidence/{evidenceId}.enc ← encrypted blob, OPT-IN ONLY
```

**Authentication: Firebase Anonymous Auth.** No email, no phone number.

This is a deliberate threat-model decision. An email or SMS confirmation arrives in an inbox the abuser may be able to read, and a phone number ties the account to a real identity. Anonymous auth leaves nothing to find. The trade-off is that account recovery across devices is hard — addressed by the recovery key in P7.

**Immutability is enforced by security rules, not by client code:**

```javascript
match /users/{uid}/evidence/{doc} {
  allow create: if request.auth != null && request.auth.uid == uid;
  allow read:   if request.auth != null && request.auth.uid == uid;
  allow update, delete: if false;   // nobody, ever — including the owner
}
```

Storage rules likewise deny overwrite (`resource == null` required on create) and deny delete outright.

**This is the strongest property in the system.** It means that once a record reaches the server, neither an abuser who seizes the phone, nor the victim under coercion, nor a developer with console access, nor an attacker with the user's credentials can delete or alter it. The client cannot opt out, because the rule is evaluated server-side.

### 3.3 What actually leaves the device 🟡

> **As built, 2026-09-23: only metadata leaves the device — nothing else.**
> Firebase Storage is not enabled on the project, so there is nowhere to put
> an encrypted blob and the app does not try. The backup control is still
> present and explains this when tapped. The table below describes the design
> once Storage is switched on; until then the "encrypted blob" row never
> happens, and the honest claim is the stronger and simpler one: **no evidence
> media has ever left the phone.**

**Decision of 2026-09-16: media stays local by default.**

| Leaves the device | When | Why it is safe to store |
|---|---|---|
| Metadata — both SHA-256 hashes, wrapped DEK, nonce, GCM tag, timestamp, size, type | **Always** | The wrapped DEK is encrypted under a master key derived from the PIN, which never leaves the device. To Firebase it is indistinguishable from noise |
| Encrypted blob | **Only when the user explicitly enables backup for that item** — and not at all today, see the note above | AES-256-GCM ciphertext. Unreadable without the PIN |
| Filename, location, notes, anything identifying | **Never** | Not collected |

**On the privacy rationale.** The decision was motivated by not wanting to hold survivor media. It is worth recording that client-side encryption already addressed that: under the original design Firebase would only ever have received ciphertext, so a breach, a subpoena or a curious operator would all have obtained the same useless bytes (adversary A6). Holding encrypted media is not the same as holding media.

The defensible justification for opt-in is different and, in this context, better: **the survivor decides what leaves their device.** In a situation where control has been taken away from someone, handing back an explicit choice is worth more than the marginal security difference. It also keeps storage costs bounded.

**The honest trade-off.** For a local-only item:

- ✅ Deletion is always **detectable** — the immutable Firestore record proves a file with that hash existed at that time, so a missing or altered file is provable.
- ❌ Deletion is **not preventable** — destroy the phone and the media is gone. The cloud holds the key, but a key without ciphertext recovers nothing.

So for local-only evidence the backend provides **integrity and non-repudiation**, not **preservation**. That is genuinely valuable — it is what a trusted timestamping authority does — but it is a weaker claim than "evidence cannot be destroyed", and the project's documentation must not blur the two.

Backed-up items get both properties. The UI must state this difference plainly at the point the user chooses, because they cannot make a real decision without it.

---

## 4. Application security

### 4.1 Discretion 🟡

| Control | Status | Notes |
|---|---|---|
| Decoy calculator front-end | 🟢 Built | Fully functional calculator, not a stub — it survives casual use |
| Hidden unlock sequence | 🟢 Built | User-chosen at first run, stored in secure storage. Must contain an operator, so ordinary calculator use can't trigger it by accident |
| Evidence never in device gallery | 🟢 Built | In-app camera writes only to app-private storage. `image_picker` is gone |
| Screenshot / recents blocking | 🟢 Built | `FLAG_SECURE`, set before the first frame is drawn |
| Panic return to calculator | 🟢 Built | Hold anywhere for 1s. The key is destroyed before anything redraws |
| Auto-lock on backgrounding | 🟢 Built | On `paused` and `hidden`, not `inactive`. A running capture defers it |
| Duress PIN → decoy vault | 🔴 Not built | P9 |

### 4.2 Access control 🟡

- 🟢 PIN is **never stored**. Verification is by attempting to unwrap the master key — a wrong PIN simply fails GCM authentication.
- 🟢 **Lockout:** 4 free attempts, then 30s → 1m → 2m → 5m → 15m → 1h (repeating). The counter and lock time are persisted in secure storage, so restarting the app does not reset them. The attempt is recorded **before** the slow key derivation starts, so killing the app mid-guess doesn't give a free try.
- 🟢 **Change PIN** goes through the same lockout. Otherwise it would be a way round it.
- 🟢 **No wipe after N failures, deliberately.** In most apps that's a security feature. Here it would hand an abuser a way to destroy the evidence just by typing wrong PINs.
- 🟢 The master key is zeroed in memory on lock (`SecretKeyData.destroy()` overwrites the bytes), and panic and backgrounding both lock.
- 🟢 A corrupted key record fails loudly (`KeyStoreCorruptedException`) instead of silently creating a new master key, which would orphan every existing file.

### 4.3 Audit log 🔴

Append-only and **hash-chained**: each entry contains the SHA-256 of the previous entry. Removing or altering any event breaks the chain at that point and is detectable by `verifyChain()`.

Recorded events: unlock, failed unlock, capture, upload, view, panic, PIN change.

Chaining matters because an append-only log alone does not prove completeness — without the chain, an attacker with write access could delete a middle entry unnoticed. With it, any gap is visible.

---

## 5. Known limitations

Stated plainly, because a security document that claims no weaknesses is not credible.

1. **Forgotten PIN means permanent data loss.** Keys never leave the device and we cannot recover them — that is the point of the design, and it is also its sharpest edge. The P7 recovery key mitigates this; until then, it is a real risk to warn users about.
2. **In-memory keys are extractable** if the device is compromised while the app is unlocked.
3. **The app's presence is itself a signal.** The decoy calculator defends against a casual look, not against someone who knows what to search for.
4. **Anonymous auth makes cross-device recovery hard.** Deliberate, but a genuine usability cost.
5. **We cannot guarantee court admissibility.** The system is designed to *support* integrity, authenticity, provenance and chain of custody. Whether evidence is admitted depends on jurisdiction, collection circumstances, and evidence law — not on software.
6. **Metadata leaks some information.** File sizes, capture timestamps and counts are visible to the backend even though content is not. Padding and timestamp coarsening are not implemented.
7. **No secure-delete guarantee on flash storage.** Wear levelling means overwriting a file does not reliably destroy the old blocks. Encryption-at-rest mitigates this: deleting the key matters more than deleting the bytes.
8. **The lockout uses the phone's clock.** Someone who moves the system clock forward can shorten a timeout. Each guess still costs a full key derivation and is still counted, so this makes guessing slower, not impossible. Root on the device bypasses the lockout entirely (see §2.2).
9. **Some key copies cannot be zeroed.** PBKDF2 runs in a separate isolate, and the Dart VM copies bytes between isolates; those copies are freed but not overwritten. Dart does not offer control over this.
10. **Local-only evidence does not survive loss of the phone.** Following the 2026-09-16 decision, media is uploaded only when the user opts in per item. For everything else the device holds the only copy, and destroying it destroys the evidence — the cloud record then proves only that the evidence once existed and what its hash was. See §3.3.

---

## 6. Dependencies

| Package | Purpose |
|---|---|
| `cryptography` | AES-256-GCM, PBKDF2/Argon2id, secure random |
| `crypto` | Streaming SHA-256 |
| `flutter_secure_storage` | Android Keystore-backed key storage |
| `firebase_auth` | Anonymous authentication |
| `cloud_firestore` | Immutable metadata records |
| `firebase_storage` | Encrypted blob storage |
| `camera` | In-app capture that bypasses the system gallery |
| `record` | Audio capture |

**We do not roll our own cryptography.** Every primitive comes from an established, audited library. The design work here is in how they are composed — the key hierarchy, the AAD binding, the server-side immutability rules — not in the primitives themselves.

---

## 7. References

- NIST SP 800-38D — Galois/Counter Mode
- NIST SP 800-132 — PBKDF2 recommendations
- OWASP Mobile Application Security Verification Standard (MASVS)
- Firebase Security Rules documentation
- ACPO / NIST SP 800-101 — principles of digital evidence handling
