# Secure Evidence — Development Checklist

**Branch for this work:** `feature/security-layer`
**Last updated:** 2026-09-12

This is the single source of truth for what is built, what is not, and what order it gets built in. Tick boxes as you go and keep the progress table at the bottom honest — it is what we quote in the review.

---

## How we work

1. **One phase at a time.** A phase is not finished until its **Gate** passes. Do not start the next phase with a failing gate — debugging two layers of unverified crypto at once is how a week disappears.
2. **Tests are written inside the phase, next to the code.** There is no "testing phase" at the end. A phase that has no passing tests is not done, it is 0%.
3. **Commit at every gate**, with the phase number in the message (`P1: crypto core`). This keeps the history readable and makes it obvious in the viva what was built when.
4. **Partial credit is per-task, not per-phase.** If a phase is half done, count the ticked tasks against the phase weight.

---

## Where we are right now

Assessed 2026-09-12 by reading every file in `lib/` (2,563 lines of Dart).

### What genuinely works

- **Decoy calculator** (`lib/features/calculator/`) — a real, working calculator: `+ − × ÷ %`, backspace, divide-by-zero error state, result formatting. Unlocks on a hidden key sequence. This is the most complete part of the app.
- **App shell** (`lib/app/app.dart`) — three-state gate: calculator → PIN → home.
- **PIN format validation** (`lib/features/auth/domain/pin_validator.dart`) — 4-digit numeric check with error messages, 8 unit tests passing.
- **Capture** — photo/video via `image_picker`, audio via `record` (AAC-LC 128kbps/44.1kHz, live duration timer, permission check).
- **Local storage** (`lib/services/storage/evidence_storage.dart`) — copies captures into `<app documents>/evidence/`, UUID filenames, JSON index in `SharedPreferences`, deliberately no delete/update method.
- **Vault UI** (`lib/features/vault/`) — list with type, filename, timestamp, size, newest-first, pull-to-refresh.
- **Home** — dashboard, quick actions, Indian helplines (181, 112, NCW 011-26944880), settings page.

### What does not exist yet

| `README.md` claims | Reality in code |
|---|---|
| AES-256-GCM, envelope encryption | **No encryption at all.** Files sit in plaintext on disk |
| SHA-256 integrity | `hash` field on `EvidenceItem` is **always `null`** |
| REST API / JWT / PostgreSQL / Cloud Storage | **No backend.** Nothing leaves the device |
| KMS / secure key management | Nothing |
| Audit logging | Nothing |
| Controlled access | PIN `2580` **hardcoded in source**; unlock sequence `1+2+3+4=` likewise |

`firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_storage`, `crypto`, `camera` and `permission_handler` are all declared in `pubspec.yaml` and **never imported anywhere**.

### Known bugs to fix (scheduled in P4)

1. **Panic button crashes.** `lib/features/home/home_page.dart:100` calls `pushReplacementNamed('/pin')`, but `MaterialApp` registers no named routes. This throws at runtime.
2. **Photos leak to the device gallery.** `image_picker` hands off to the system camera app, so captures can persist in DCIM — exactly where an abuser holding the phone would find them.
3. **"Read-only database" is a comment, not a mechanism.** The `SharedPreferences` index is trivially readable and writable.
4. Settings toggles (auto-lock, biometric) and "Change PIN" are dead UI.

**Starting point: ~25-30% complete.**

---

## Progress weights

| Phase | Scope | Weight | In review scope (8 days)? |
|---|---|---|---|
| P0 | Planning, docs, honest README | 4% | Yes |
| P1 | Crypto core (AES-256-GCM + SHA-256) | 14% | Yes |
| P2 | Key & PIN management | 11% | Yes |
| P3 | Storage hardening | 9% | Yes |
| P4 | Safety & discretion fixes | 9% | Yes |
| P5 | Firebase backend + immutability rules | 13% | Yes |
| P6 | Tamper-evident audit log | 10% | Start only |
| P7 | Integrity verification & court export | 13% | No |
| P8 | Offline sync queue | 9% | No |
| P9 | Hardening, duress PIN, CI, final docs | 8% | No |

**Review target: P0-P5 complete (60%) + P6 half (5%) = 65%.**

---

## P0 — Planning & documentation · 4%

No feature code in this phase. Deliberate: we agree the map before anyone drives.

- [x] Create branch `feature/security-layer` off `main`
- [x] Write `DEVELOPMENT_CHECKLIST.md` (this file)
- [x] Write `docs/SECURITY.md` — algorithms, key hierarchy, threat model, and an explicit list of what is **not** protected
- [x] Correct `README.md` — status markers throughout, "Current Status" section, Technology split into in-use vs planned
- [ ] Teammate reads the checklist and agrees the phase split
- [ ] Install Flutter SDK on Akash's machine (currently absent — `flutter test` / `flutter analyze` cannot run locally)

> **Why the README correction matters:** the README currently claims shipped AES-256, JWT and PostgreSQL. If an examiner asks to see the encryption and it does not exist, the whole project's credibility goes with it. A README that says "planned" costs us nothing and protects us.

**Gate:** all three documents committed and pushed. Teammate has confirmed.

---

## P1 — Crypto core · 14%

The heart of the project. Everything after this depends on it, which is why it goes first and gets the most test coverage.

> ⚠️ **P1 is written but UNVERIFIED.** No Flutter SDK is installed on the
> development machine, so `flutter pub get`, `flutter analyze` and
> `flutter test` have never been run against this code. It has not
> compiled once. Treat the code below as a first draft until the gate
> passes. Most likely places to need adjustment are flagged inline.

### Setup
- [x] Add `cryptography` and `flutter_secure_storage` to `pubspec.yaml` — **hand-written constraints (`^2.7.0`, `^9.2.2`), not resolved by pub. Verify with `flutter pub get`**
- [x] Keep the existing `crypto` package — it is used for streaming SHA-256
- [ ] Run `flutter pub get` and confirm the constraints resolve

### Implementation — `lib/services/crypto/crypto_service.dart` (new)
- [x] Generate a random 256-bit **DEK** (data encryption key) per file
- [x] Stream **SHA-256 of the plaintext** via `sha256.bind(file.openRead())` — never load a 30-minute video into memory. This is the evidentiary hash
- [x] Encrypt with **AES-256-GCM** (`AesGcm.with256bits()`), fresh random 96-bit nonce per file
- [x] Bind the plaintext SHA-256 in as **AAD**, so ciphertext and hash cannot be mismatched
- [x] Wrap the DEK with the master KEK — `encryptFile()` takes the KEK as a parameter, so P2 wires `KeyManager` in without touching this file
- [x] Compute SHA-256 of the ciphertext for transport integrity
- [x] Blob written to the caller's destination; nonce, tag, wrapped DEK and both hashes returned in `EncryptionResult`, never in the blob
- [x] Public API: `encryptFile()`, `decryptToFile()`, `decryptToTemp()`, `verifyIntegrity()`, `verifyCiphertext()`, `hashFile()`, `hashBytes()`
- [x] `decryptToTemp()` targets a temp file the caller must delete on dispose — plaintext never re-enters the evidence directory
- [x] Failed decryption deletes the partial output rather than leaving half a file that looks like evidence
- [ ] **Verify `encryptStream` / `decryptStream` signatures against the resolved `cryptography` version.** These are the least certain part of the file — written without a compiler. If they differ, this is where it breaks

### Implementation — `lib/models/evidence/evidence_item.dart` (modify)
- [x] Add `plaintextSha256`, `ciphertextSha256`, `wrappedDek`, `nonce`, `gcmTag`, `encryptionAlgorithm`, `keyVersion`
- [x] Replace the always-null `hash` field with `plaintextSha256`
- [x] Keep `toMap` / `fromMap` / `toJson` / `fromJson` round-tripping with the new fields
- [x] Add `EvidenceItem.encrypted()` factory and an `isEncrypted` flag — crypto fields stay nullable until storage routes through `CryptoService` in P3
- [x] Update the one caller in `evidence_storage.dart` that set `hash: null`

### Tests — `test/services/crypto_service_test.dart` (new, 23 cases)
- [x] Round-trip: encrypt → decrypt → bytes byte-identical
- [x] Empty file round-trips
- [x] Encrypted blob does not contain the plaintext
- [x] Two encryptions of the same file produce different ciphertext (proves no nonce reuse)
- [x] SHA-256 is stable across runs for the same input
- [x] SHA-256 differs for a one-byte change
- [x] SHA-256 matches the NIST `"abc"` test vector
- [x] Large-file streaming: a synthetic 50MB file hashes without exhausting heap
- [x] **Tamper detection:** flipped ciphertext byte → authentication throws
- [x] **Tamper detection:** truncated blob → authentication throws
- [x] **AAD tamper detection:** substituted plaintext hash → decryption fails
- [x] Modified GCM tag → authentication throws
- [x] Wrong master key → `EvidenceIntegrityException`
- [x] Truncated wrapped key → `EvidenceIntegrityException`
- [x] No partial plaintext left behind after a failed decryption
- [x] `verifyIntegrity` passes for untouched evidence, returns false (not throws) for tampered
- [x] `verifyCiphertext` detects storage corruption
- [x] Metadata: algorithm, key version, sizes, hash lengths
- [x] Nonce is 96 bits, tag is 128 bits, wrapped DEK is 60 bytes
- [x] `EvidenceItem` round-trips every crypto field through JSON
- [x] `isEncrypted` false for a pre-encryption record, true once metadata is present

**Gate — ⛔ BLOCKED, not passed:**
- [ ] `flutter pub get` resolves
- [ ] `flutter analyze` clean
- [ ] `flutter test` green — **none of the 23 tests above has ever been executed**
- [x] Committed as a draft so the work is not lost

> **Do not count P1 toward the completion percentage until the gate passes.** Code that has never compiled is not 14%.

---

## P2 — Key & PIN management · 11%

Replaces the hardcoded `2580`. This is where the app stops being a mockup.

### Implementation — `lib/services/crypto/key_manager.dart` (new)
- [ ] **Master key (KEK):** random 256 bits, generated once at first run
- [ ] **PIN-derived key:** PBKDF2-HMAC-SHA256 at **≥150,000 iterations** (or Argon2id) over PIN + random 128-bit salt
- [ ] Master key is **wrapped by the PIN-derived key**, stored in `flutter_secure_storage` (Android Keystore-backed)
- [ ] The PIN itself is **never stored** — a wrong PIN simply fails to unwrap the master key
- [ ] Master key lives in memory only while unlocked; zeroed on lock and on panic

### Implementation — auth flow
- [ ] `lib/features/auth/domain/pin_validator.dart` — delete `secretPin = '2580'` and `matchesSecret()`. Keep format validation (its 8 tests must still pass). Verification moves to `KeyManager.unlock(pin)`
- [ ] `lib/features/auth/presentation/pin_page.dart` — first-run "set your PIN" flow (enter + confirm), then normal unlock
- [ ] Failed-attempt lockout with exponential backoff; counter persisted so a restart does not reset it
- [ ] `lib/features/calculator/presentation/calculator_page.dart` — `_developmentSecret = '1+2+3+4='` becomes user-configurable, stored in secure storage
- [ ] `lib/features/home/home_page.dart` — wire the dead "Change PIN" tile: re-wrap the master key under a new PIN, **without** re-encrypting any evidence
- [ ] Document in `docs/SECURITY.md`: keys never leave the device, so a forgotten PIN means permanently unrecoverable evidence. Recovery key is P7

> **Worth being able to explain live:** changing the PIN re-wraps one 256-bit key, not 4GB of video. That is the entire reason for envelope encryption, and it is the kind of thing examiners probe.

### Tests — `test/services/key_manager_test.dart` (new)
- [ ] Correct PIN unwraps the master key
- [ ] Wrong PIN fails to unwrap
- [ ] **PIN change:** files encrypted under the old PIN still decrypt afterwards
- [ ] Same PIN + different salt → different derived key
- [ ] Lockout backoff increases with each failure and survives a simulated restart
- [ ] KDF iteration count is at least the configured minimum (guards against someone lowering it for test speed and forgetting)
- [ ] The existing 8 `PinValidator` tests still pass

**Gate:** `flutter test` green · manual first-run, unlock and change-PIN on device · commit `P2: key and PIN management`

---

## P3 — Storage hardening · 9%

Makes "read-only" and "encrypted at rest" true locally.

### Implementation
- [ ] `lib/services/storage/evidence_storage.dart` — route `addEvidence()` through `CryptoService`
- [ ] Preserve the existing copy-then-store ordering (the current comment about not moving the source is correct)
- [ ] **Securely delete the plaintext source** after a verified write
- [ ] `lib/services/storage/evidence_index.dart` (new) — replace the `SharedPreferences` index with an AES-256-GCM encrypted `index.enc` in app documents
- [ ] Running hash over the index so silent edits are detectable
- [ ] Keep the append-only discipline: still no `deleteEvidence()` / `updateEvidence()`

> **Note:** any evidence captured during earlier development becomes unreadable after this change. There is no production data, so no migration is needed — just clear app data when testing.

### Tests — `test/services/evidence_storage_test.dart`, `test/services/evidence_index_test.dart` (new)
- [ ] Add evidence → the stored file is **not** byte-identical to the source (proves encryption actually ran, rather than assuming it did)
- [ ] Stored blob contains no recognizable file-format magic header (no `JFIF`, no `ftyp`)
- [ ] Index round-trips: write N items, reload, all fields intact
- [ ] Newest-first ordering preserved (existing behaviour in `getEvidence()`)
- [ ] **Corrupt `index.enc` → load fails loudly.** The current `getEvidence()` silently returns `[]` on malformed data; that must not survive into the encrypted index — silently showing an empty vault to someone whose evidence still exists is the worst possible failure mode here
- [ ] Plaintext source file is gone after a successful add
- [ ] `EvidenceStorage` still exposes no delete or update method

**Gate:** `flutter test` green · `adb pull` a stored blob and confirm it is unreadable · commit `P3: encrypted storage`

---

## P4 — Safety & discretion fixes · 9%

Correctness bugs with direct safety consequences for the people this app is for.

### 1. Panic button (currently crashes)
- [ ] `lib/app/app_lock_controller.dart` (new) — a `ChangeNotifier` holding `locked` / `showPin` / `unlocked`, replacing the three `setState` booleans in `_SecureEvidenceAppState`
- [ ] Panic: zero keys in memory → pop to root → calculator with a cleared display
- [ ] Fix `lib/features/home/home_page.dart:100` — `pushReplacementNamed('/pin')` throws because no named routes are registered
- [ ] Add a long-press trigger so panic works without navigating home first

### 2. Stop photos leaking into the gallery
- [ ] `lib/features/evidence/capture/in_app_camera_page.dart` (new) — in-app capture using the `camera` package (already in `pubspec.yaml`, currently unused), writing straight to app temp
- [ ] Retire `image_picker` for camera capture in `camera_capture_page.dart`

### 3. Screen privacy
- [ ] `FLAG_SECURE` in `MainActivity.kt` — blocks screenshots and the recents-screen thumbnail

### 4. Auto-lock
- [ ] `WidgetsBindingObserver` on `AppLifecycleState.paused` / `inactive` → lock immediately, drop keys
- [ ] Wire the currently-dead auto-lock toggle in `_SettingsPageState` and persist the preference

### Tests — `test/app/app_lock_controller_test.dart`, `test/widget/panic_test.dart` (new)
- [ ] Panic transitions unlocked → calculator and clears the in-memory key reference
- [ ] After panic, reaching the vault again requires the PIN
- [ ] Lifecycle `paused` locks when auto-lock is on
- [ ] Lifecycle `paused` does not lock when auto-lock is off
- [ ] Widget test: pump app → unlock → panic → `CalculatorPage` showing and display reads `0`
- [ ] Existing `test/widget_test.dart` smoke test still passes

**Gate:** `flutter test` green · manual device pass on all four items — **especially: capture a photo, then open a file manager and confirm it is not in DCIM** · commit `P4: safety fixes`

---

## P5 — Firebase backend & immutability · 13%

Where "secure read-only database" stops being a claim and becomes something we can demonstrate being enforced.

### Setup
- [ ] `flutterfire configure` → generates `lib/firebase_options.dart` and `android/app/google-services.json`
- [ ] Add `com.google.gms.google-services` plugin in `android/app/build.gradle.kts` and the classpath in `android/build.gradle.kts`
- [ ] **Add `google-services.json` and `firebase_options.dart` to `.gitignore`** — do not commit project credentials
- [ ] `Firebase.initializeApp()` in `lib/main.dart`
- [ ] Change `applicationId` off the default `com.example.secure_evidence_app`

### Auth
- [ ] Firebase **Anonymous Auth** — no email, no phone

> **Why anonymous:** an email or SMS confirmation lands in an inbox the abuser may have access to. Anonymous auth leaves no trace tying the account to the survivor. This is a deliberate threat-model decision, not laziness — say so in the review.

### Data model
- [ ] Firestore `/users/{uid}/evidence/{evidenceId}` — metadata only (hashes, nonce, wrapped DEK, timestamps, size, type)
- [ ] Storage `/users/{uid}/evidence/{evidenceId}.enc` — encrypted blob only
- [ ] `lib/services/sync/firebase_evidence_repository.dart` (new) — **upload blob first, then write metadata**, so a metadata record never points at a missing file

### Security rules — `firestore.rules`, `storage.rules` (new)
- [ ] Firestore: `allow create` and `allow read` for own uid only; **`allow update, delete: if false`**
- [ ] Storage: `allow create: if resource == null` (no overwrite); **`allow delete: if false`**

### Tests
- [ ] **Rules tests** (`test/rules/evidence_rules.test.js`, Firebase emulator + `@firebase/rules-unit-testing`) — this is the headline deliverable of the phase:
  - [ ] Create succeeds for own uid
  - [ ] Create denied for another user's uid
  - [ ] **Update denied**
  - [ ] **Delete denied**
  - [ ] Read denied when unauthenticated
  - [ ] Storage overwrite denied
- [ ] Dart: repository uploads blob before metadata
- [ ] Dart: a failed blob upload writes no metadata record
- [ ] Dart: the uploaded payload contains no plaintext (assert on bytes handed to the mock)

**Gate:** rules tests green against the emulator · `flutter test` green · one real capture visible in the Firebase console · **delete attempt denied in the rules playground** · commit `P5: firebase backend and immutable rules`

---

## P6 — Tamper-evident audit log · 10% *(start only before review)*

### Implementation — `lib/services/audit/audit_log.dart` (new)
- [ ] Append-only, **hash-chained**: each entry stores SHA-256 of the previous entry
- [ ] Events: unlock, failed unlock, capture, upload, view, panic, PIN change
- [ ] `verifyChain()` walks the log and reports the first break
- [ ] Write to `/users/{uid}/audit/{eventId}` under the same create-only rules *(after review)*
- [ ] Audit-viewer UI *(after review)*

### Tests
- [ ] Chain verifies over a clean log
- [ ] Altering any middle entry fails verification
- [ ] Deleting an entry fails verification
- [ ] The first entry anchors correctly

**Gate:** local chain + verification working, tests green.

---

## P7 — Integrity verification & court export · 13% *(after review)*

- [ ] Evidence detail screen with photo/video/audio playback from decrypted temp
- [ ] "Verify integrity" action — re-hash and compare against stored `plaintextSha256`, show pass/fail
- [ ] Integrity badge in the vault list (replacing the current hardcoded "STORED" label)
- [ ] Court-export bundle: decrypted evidence + PDF manifest of hashes, timestamps and chain of custody
- [ ] One-time printable **recovery key** so a forgotten PIN is not permanent data loss
- [ ] Tests: verification detects a modified blob; export manifest hashes match the stored ones

---

## P8 — Offline sync queue · 9% *(after review)*

- [ ] Queue uploads when offline, retry with exponential backoff
- [ ] Per-item sync status in the vault (local / syncing / synced)
- [ ] Never delete the local copy after upload — the device copy is the fallback
- [ ] Tests: queue survives restart; retry backs off; no duplicate uploads

---

## P9 — Hardening, duress PIN, CI, final docs · 8% *(after review)*

- [ ] **Duress PIN** — a second PIN that opens a decoy vault with innocuous content
- [ ] Biometric unlock (wire the dead toggle in settings)
- [ ] `flutter analyze` clean across the whole project
- [ ] CI running `flutter analyze` + `flutter test` on push
- [ ] Release signing config (currently signing with debug keys — see the TODO in `android/app/build.gradle.kts`)
- [ ] Final `docs/SECURITY.md` and architecture diagram for the report

---

## Progress tracker

Update this after every gate.

| Phase | Weight | Status | Done |
|---|---|---|---|
| P0 Planning & docs | 4% | In progress | 4/6 tasks |
| P1 Crypto core | 14% | ⛔ Written, gate blocked | Code + 23 tests written, **never compiled or run** |
| P2 Key & PIN management | 11% | Not started | — |
| P3 Storage hardening | 9% | Not started | — |
| P4 Safety fixes | 9% | Not started | — |
| P5 Firebase + rules | 13% | Not started | — |
| P6 Audit log | 10% | Not started | — |
| P7 Verification & export | 13% | Not started | — |
| P8 Offline sync | 9% | Not started | — |
| P9 Hardening & CI | 8% | Not started | — |

**Baseline before this branch: ~27%** (UI, decoy calculator, capture, plaintext local storage)
**Current: ~28%** — P1 code exists but does not count until it compiles and its tests pass
**Review target: 65%**

> 🚨 **Blocking the whole schedule: no Flutter SDK on the development
> machine.** Every phase gate from P1 onward depends on `flutter test`.
> Install the SDK before continuing, or move development to the
> teammate's machine. Writing more unverified phases on top of an
> unverified P1 is how a crypto bug reaches the demo.

---

## 8-day schedule

| Day | Phase |
|---|---|
| 1 | P0 — checklist, security doc, README, install Flutter, add deps |
| 2-3 | P1 — crypto core + tests |
| 4 | P2 — key manager, PIN flows + tests |
| 5 | P3 — encrypted storage + index + tests |
| 6 | P4 — safety fixes + tests |
| 7 | P5 — Firebase, rules + rules tests |
| 8 | Buffer, start P6, demo run-through, screenshots |

---

## Demo run-through for the review

On a **real Android device** — an emulator does not properly exercise the Keystore.

1. First run → set PIN → calculator appears
2. Wrong unlock sequence does nothing; correct sequence → PIN screen; wrong PIN → lockout backoff
3. Capture a photo → open a file manager → **it is not in DCIM**
4. `adb pull` the `.enc` file → it is not a viewable image
5. It appears in the vault and decrypts for viewing
6. Panic from the vault → instantly a cleared calculator; re-entry requires the PIN
7. Background the app → auto-lock fires. Screenshot → blocked
8. Firebase console: blob in Storage, metadata in Firestore. **Then attempt delete and update from the rules playground — both denied**

> Lead with step 8. Server-enforced immutability is the strongest claim this project can make, and it is the one thing a marker cannot dismiss as UI.
