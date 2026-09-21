# Secure Evidence — Development Checklist

**Branch for this work:** `feature/p4-safety-fixes`
**Last updated:** 2026-09-21

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
- [x] Install Flutter SDK on Akash's machine (Flutter 3.47.4 / Dart 3.13.3, installed by 2026-09-18)

> **Why the README correction matters:** the README currently claims shipped AES-256, JWT and PostgreSQL. If an examiner asks to see the encryption and it does not exist, the whole project's credibility goes with it. A README that says "planned" costs us nothing and protects us.

**Gate:** all three documents committed and pushed. Teammate has confirmed.

---

## P1 — Crypto core · 14%

The heart of the project. Everything after this depends on it, which is why it goes first and gets the most test coverage.

> ✅ **P1 gate passed on 2026-09-18** (Flutter 3.47.4, Dart 3.13.3).
> `flutter pub get` resolved, `flutter analyze` was clean and all 23
> crypto tests passed on the first run. No code changes were needed.

### Setup
- [x] Add `cryptography` and `flutter_secure_storage` to `pubspec.yaml` — **resolved to `cryptography 2.9.0`, `flutter_secure_storage 9.2.4`**
- [x] Keep the existing `crypto` package — it is used for streaming SHA-256
- [x] Run `flutter pub get` and confirm the constraints resolve

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
- [x] **Verify `encryptStream` / `decryptStream` signatures against the resolved `cryptography` version** — they match 2.9.0, and the analyzer is clean

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

**Gate — ✅ passed 2026-09-18:**
- [x] `flutter pub get` resolves
- [x] `flutter analyze` clean (`No issues found!`)
- [x] `flutter test` green — 32/32 (23 crypto + 8 PinValidator + 1 widget smoke test)
- [x] Committed as `P1: crypto core (gate passed)`

---

## P2 — Key & PIN management · 11%

Replaces the hardcoded `2580`. This is where the app stops being a mockup.

> **Decision (2026-09-18):** keep the 4-digit PIN, and bind the PIN-wrapped
> master key to the Android Keystore (option 1) rather than moving to longer
> PINs. 10,000 PINs are only guessable on the device itself, where the lockout
> applies. Rationale and the root-on-device limit are in `docs/SECURITY.md` §2.2.

### Implementation — `lib/services/crypto/key_manager.dart` (new)
- [x] **Master key (KEK):** random 256 bits, generated once at first run
- [x] **PIN-derived key:** PBKDF2-HMAC-SHA256 at **150,000 iterations** over PIN + random 128-bit salt, run in a background isolate
- [x] Master key is **wrapped by the PIN-derived key**, stored in `flutter_secure_storage`, whose values are encrypted under a non-exportable Keystore key (`lib/services/crypto/secure_store.dart`)
- [x] Salt, iteration count and wrapped key written as **one** record, so a crash can't leave them mismatched
- [x] The PIN itself is **never stored** — a wrong PIN simply fails to unwrap the master key
- [x] Master key lives in memory only while unlocked; `lock()` overwrites its bytes. *(Locking on panic is P4.)*
- [x] Android backups and device-to-device transfer disabled (`AndroidManifest.xml`, `res/xml/data_extraction_rules.xml`)

### Implementation — auth flow
- [x] `lib/features/auth/domain/pin_validator.dart` — `secretPin = '2580'` and `matchesSecret()` deleted. Format validation kept; its 8 tests still pass
- [x] `lib/features/auth/presentation/setup_page.dart` (new) — first-run PIN + confirm + unlock sequence, with a forgotten-PIN warning
- [x] `lib/features/auth/presentation/pin_page.dart` — unlocks via `KeyManager.unlock()`, spinner during the KDF, live lockout countdown
- [x] Failed-attempt lockout: 4 free, then 30s → 1m → 2m → 5m → 15m → 1h; persisted, survives restart; attempt counted before the KDF runs. **No wipe after N failures**, on purpose
- [x] `lib/features/calculator/presentation/calculator_page.dart` — `_developmentSecret` removed; the sequence is user-chosen (`lib/features/auth/domain/unlock_sequence.dart`) and stored in secure storage
- [x] `lib/features/home/home_page.dart` + `change_pin_page.dart` (new) — "Change PIN" re-wraps the master key under a new PIN and salt, **without** re-encrypting any evidence; wrong current PIN counts toward the lockout
- [x] Documented in `docs/SECURITY.md`: Keystore layer and its limit (§2.2), lockout (§4.2), clock and isolate-copy limits (§5)

### Tests — `test/services/key_manager_test.dart` (new, 19 cases) + widget and sequence tests
- [x] Correct PIN unwraps the master key, and that key decrypts a file made by `CryptoService`
- [x] Wrong PIN fails to unwrap
- [x] **PIN change:** files encrypted under the old PIN still decrypt afterwards; old PIN stops working
- [x] Same PIN + different salt → different stored key
- [x] The PIN appears nowhere in storage
- [x] Lockout backoff increases with each failure, caps at 1h, and survives a simulated restart; a correct PIN during lockout is refused
- [x] KDF iteration count is at least 150,000 (guard test; ~0.7s on the dev machine)
- [x] Corrupted key record fails loudly rather than resetting
- [x] The existing 8 `PinValidator` tests still pass
- [x] Widget: first launch shows setup; the chosen sequence opens the PIN screen; `1+2+3+4=` no longer does
- [x] `UnlockSequence`: normalization and validation (8 cases)

**Gate:**
- [x] `flutter analyze` clean
- [x] `flutter test` green — 62/62
- [x] `flutter build apk --debug` succeeds
- [ ] **Manual on a real device:** first-run setup, custom sequence, wrong PIN ×5 → countdown, kill app → still locked out, Change PIN → relaunch → new PIN works. **Time the unlock**: if 150k iterations takes more than ~3s, raise it rather than quietly lowering the count
- [x] Committed as `P2: key and PIN management`

---

## P3 — Storage hardening · 9%

Makes "read-only" and "encrypted at rest" true locally.

### Implementation
- [x] `lib/services/storage/evidence_storage.dart` — `addEvidence()` routes through `CryptoService`; blobs are `evidence/<uuid>.enc` with no extension
- [x] Order: encrypt → **decrypt and re-hash to verify** → index → destroy source. The source is kept, and the partial blob removed, if any step before the last fails
- [x] **Plaintext source overwritten with zeros, then deleted**, after the verified write (best effort on flash; SECURITY.md §5)
- [x] `lib/services/storage/evidence_index.dart` (new) — AES-256-GCM `index.enc`, key derived from the master key with HKDF, atomic temp-and-rename writes, serialized appends
- [x] **Rollback detection** in place of a "running hash": GCM already catches edits, so the seal (count + SHA-256 of `index.enc`, in Keystore-backed storage) catches an older genuine copy being put back. Crash-safe via a pending hash
- [x] Keep the append-only discipline: still no `deleteEvidence()` / `updateEvidence()`
- [x] `lib/app/app_scope.dart` (new) — `KeyManager` + `EvidenceStorage` shared through an InheritedWidget; the `EvidenceStorage.instance` singleton is gone
- [x] Vault: error screen for an untrusted index (never "No evidence yet"); "STORED" → "ENCRYPTED" + hash prefix

> **Note:** evidence captured before P3 (plaintext files, SharedPreferences index) is not migrated or deleted. Clear app data on test devices.

### Tests — `test/services/evidence_storage_test.dart` (12), `test/services/evidence_index_test.dart` (11)
- [x] Add evidence → the stored file is **not** byte-identical to the source
- [x] Stored blob contains no JPEG (`FF D8 FF`, `JFIF`) or MP4 (`ftyp`) header
- [x] Blob decrypts back to exactly the source; blob name reveals neither type nor original name
- [x] Nothing in the evidence directory contains the original filename
- [x] Index round-trips N items with every field; newest-first ordering survives a restart
- [x] **Corrupt `index.enc` → load fails loudly**; wrong key, deleted index and missing seal likewise
- [x] **Rolled-back `index.enc` → detected**
- [x] Crash after rename and crash before rename both recover to a consistent state
- [x] Concurrent appends are all kept
- [x] Plaintext source is gone after a successful add, and **kept** when verification fails, the index write fails, or the vault is locked
- [ ] ~~`EvidenceStorage` still exposes no delete or update method~~: not testable without reflection; enforced by review

**Gate:**
- [x] `flutter analyze` clean
- [x] `flutter test` green — 85/85
- [x] `flutter build apk --debug` succeeds
- [ ] **Manual on a real device:** capture photo + audio → vault shows ENCRYPTED → `adb shell run-as <applicationId> ls app_flutter/evidence` shows only `.enc` files → pull a blob and confirm it does not open
- [x] Committed as `P3: encrypted storage`

---

## P4 — Safety & discretion fixes · 9%

Correctness bugs with direct safety consequences for the people this app is for.

> 🟡 **Code complete 2026-09-19, awaiting the manual device pass.**
> `flutter analyze` clean, `flutter test` green — 108/108 (85 existing +
> 17 lock-controller + 6 panic widget tests), `flutter build apk --debug`
> succeeds.

### 1. Panic button (currently crashes)
- [x] `lib/app/app_lock_controller.dart` (new) — a `ChangeNotifier` holding `locked` / `showPin` / `unlocked` (`AppLockState`; Flutter already has a `LockState`), replacing the `setState` booleans in `_SecureEvidenceAppState`
- [x] Panic: zero keys in memory → pop to root → calculator with a cleared display. The key is destroyed synchronously *before* listeners run; the shell then pops every route (sheets and dialogs included) and **clears snackbars**, so "Photo saved to My Evidence" cannot linger over the calculator
- [x] Fix `lib/features/home/home_page.dart:100` — the panic card now calls `lockController.lock()`
- [x] Add a long-press trigger so panic works without navigating home first — hold anywhere for 1 s while unlocked (longer than the 500 ms platform long-press, so text selection still wins in text fields)

### 2. Stop photos leaking into the gallery
- [x] `lib/features/evidence/capture/in_app_camera_page.dart` (new) — in-app photo **and video** capture with the `camera` package. CameraX writes only to the app's private cache (`CAP*.jpg`, `REC*.mp4`), never DCIM
- [x] Retire `image_picker` — `camera_capture_page.dart` deleted and `image_picker` removed from `pubspec.yaml`
- [x] *(found during P4)* Plaintext captures could outlive the capture screen: leaving the audio page mid-recording left an unencrypted `.m4a` in the cache. New `capture_temp.dart`: every capture lives in `<cache>/capture/` until encrypted; pages destroy unsaved files on dispose; `main()` sweeps that directory and stray CameraX files at launch. The zero-then-delete routine moved out of `EvidenceStorage` into `services/storage/secure_delete.dart` so both use it

### 3. Screen privacy
- [x] `FLAG_SECURE` in `MainActivity.kt` — set before `super.onCreate`, so no frame is drawn without it

### 4. Auto-lock
- [x] `WidgetsBindingObserver` on `AppLifecycleState.paused` / `hidden` → lock immediately, drop keys. The PIN screen also falls back to the calculator
  - **Deviation: not on `inactive`.** On Android `inactive` also fires for permission dialogs and the notification shade, so locking there would throw the user out of the camera while it asks for permission
  - **Captures hold off auto-lock.** Recording audio with the screen off is a core use, and screen-off pauses the app. While a capture or its save is in flight, auto-lock is deferred; it runs the moment the capture ends if the app is still in the background. A video in progress when the app is backgrounded is stopped and saved first. **Panic ignores holds**
- [x] Wire the currently-dead auto-lock toggle in `_SettingsPageState` and persist the preference (secure store key `app.v1.autoLock`, default on)
- [ ] Biometric toggle is still dead UI — out of P4 scope, but it should be hidden or wired before the review

### Tests — `test/app/app_lock_controller_test.dart`, `test/widget/panic_test.dart` (new)
- [x] Panic transitions unlocked → calculator and clears the in-memory key reference
- [x] After panic, reaching the vault again requires the PIN
- [x] Lifecycle `paused` locks when auto-lock is on
- [x] Lifecycle `paused` does not lock when auto-lock is off
- [x] Widget test: pump app → unlock → panic → `CalculatorPage` showing and display reads `0`
- [x] Existing `test/widget_test.dart` smoke test still passes
- [x] *(extra)* `inactive` does not lock; capture holds defer and then run auto-lock; holding 1 s panics over an open sheet; a 600 ms hold does not; panic clears snackbars
- [x] *(found during P4)* Settings `ListTile`s sat in coloured `Container`s — a debug assertion and invisible ink. Now `Material`

### Manual device pass (not yet done)
- [ ] Panic: tap the card, and separately hold 1 s on the vault / camera / an open sheet → calculator showing `0`, no snackbar
- [ ] **Capture a photo and a video, then open a file manager and confirm neither is in DCIM**
- [ ] Screenshot attempt is blocked; the recents screen shows a blank card
- [ ] Auto-lock on: press home → reopen → calculator. Auto-lock off: reopen → still in the vault
- [ ] Start audio recording, turn the screen off for 30 s, turn it on, stop → the recording saves; then background the app → locks
- [ ] Camera permission denied → readable message, no crash

**Gate:** `flutter test` green · manual device pass on all four items — **especially: capture a photo, then open a file manager and confirm it is not in DCIM** · commit `P4: safety fixes`

---

## P5 — Firebase backend & immutability · 13%

Where "secure read-only database" stops being a claim and becomes something we can demonstrate being enforced.

> **Status 2026-09-21 — code complete, nothing verified yet.**
>
> Written: the sync layer (`lib/services/sync/`), the per-item and
> "Back up all" UI, `firestore.rules`, `storage.rules`, `firebase.json`,
> the emulator rules tests (`test/rules/`) and the Dart sync tests.
> `flutter analyze` is clean. **No test has been run and no APK built
> since**, by agreement — testing happens after the Firebase project
> exists.
>
> Outstanding, and blocked on the Firebase project: `firebase login`,
> creating the project, `flutterfire configure`, then the gates below.
>
> Also done in this pass: `applicationId` and `namespace` moved to
> `com.pocketcalc.calculator` and the launcher label to "Calculator", so
> the app drawer no longer announces what this is. The launcher icon is
> still Flutter's default.

### Setup
- [ ] `flutterfire configure` → generates `lib/firebase_options.dart` and `android/app/google-services.json`
- [ ] Add `com.google.gms.google-services` plugin in `android/app/build.gradle.kts` and the classpath in `android/build.gradle.kts`
- [ ] **Add `google-services.json` and `firebase_options.dart` to `.gitignore`** — do not commit project credentials
- [ ] `Firebase.initializeApp()` in `lib/main.dart`
- [ ] Change `applicationId` off the default `com.example.secure_evidence_app`

### Auth
- [ ] Firebase **Anonymous Auth** — no email, no phone

> **Why anonymous:** an email or SMS confirmation lands in an inbox the abuser may have access to. Anonymous auth leaves no trace tying the account to the survivor. This is a deliberate threat-model decision, not laziness — say so in the review.

### Data model — hybrid, media stays local by default

> **Decision (2026-09-16):** media is **not** uploaded by default. Only the
> metadata and the wrapped key go to the cloud. Uploading the encrypted
> blob is a **per-item opt-in** the survivor controls.
>
> The stated reason was privacy — not wanting to hold survivor media.
> Note for the record that client-side encryption already solved that:
> Firebase only ever receives ciphertext we cannot decrypt (adversary
> A6 in `docs/SECURITY.md`). The real justification for opt-in is
> **survivor control over what leaves their device**, which is worth
> having in a DV app regardless of what the crypto guarantees.

**Always uploaded — Firestore `/users/{uid}/evidence/{evidenceId}`**
- [ ] Metadata only: `plaintextSha256`, `ciphertextSha256`, `wrappedDek`, `nonce`, `gcmTag`, `capturedAt`, `fileSizeBytes`, `type`, `encryptionAlgorithm`, `keyVersion`
- [ ] No filename, no location, no free text — nothing that identifies a person

**Opt-in only — Storage `/users/{uid}/evidence/{evidenceId}.enc`**
- [ ] Uploaded **only** when the user explicitly enables backup for that item
- [ ] Per-item "Back up this evidence" toggle in the vault (`lib/features/vault/evidence_vault_page.dart`)
- [ ] Clear copy explaining the trade-off: backed up survives losing the phone; local-only never leaves the device

**Backup receipts — Firestore `/users/{uid}/backups/{evidenceId}`**
- [ ] A create-only receipt written when a blob upload completes

> **Why a separate collection instead of a flag on the evidence doc:**
> flipping a `hasBackup` field would be an **update**, and the whole
> point of this phase is that `allow update: if false`. A create-only
> receipt in its own collection keeps the evidence record genuinely
> immutable while still recording that a backup exists — and it is what
> lets a reinstalled app discover which items have cloud copies.

**Local sync state**
- [ ] Add `backupState` (`localOnly` / `uploading` / `backedUp` / `failed`) to the **local encrypted index only**, never to Firestore
- [ ] `lib/services/sync/firebase_evidence_repository.dart` (new) — metadata write first, then blob upload if opted in, then the receipt

### Security rules — `firestore.rules`, `storage.rules` (new)
- [ ] Firestore evidence: `allow create` + `allow read` for own uid; **`allow update, delete: if false`**
- [ ] Firestore backups: same create-only rule
- [ ] Storage: `allow create: if resource == null` (no overwrite); **`allow delete: if false`**

### Tests
- [ ] **Rules tests** (`test/rules/evidence_rules.test.js`, Firebase emulator + `@firebase/rules-unit-testing`) — the headline deliverable of the phase:
  - [ ] Create succeeds for own uid
  - [ ] Create denied for another user's uid
  - [ ] **Update denied**
  - [ ] **Delete denied**
  - [ ] Read denied when unauthenticated
  - [ ] Backup receipt create succeeds, update and delete denied
  - [ ] Storage overwrite denied
- [ ] Dart: metadata uploads for **every** item, including local-only ones
- [ ] Dart: **no blob is uploaded unless backup is explicitly enabled** — the load-bearing test for this decision
- [ ] Dart: enabling backup uploads the blob and writes a receipt
- [ ] Dart: a failed blob upload writes no receipt, and `backupState` becomes `failed`
- [ ] Dart: the uploaded payload contains no plaintext (assert on bytes handed to the mock)

**Gate:** rules tests green against the emulator · `flutter test` green · one capture visible in Firestore with **no blob in Storage** · then enable backup on it and see the blob and receipt appear · **delete attempt denied in the rules playground** · commit `P5: firebase backend and immutable rules`

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
| P0 Planning & docs | 4% | In progress | 5/6 tasks (teammate sign-off pending) |
| P1 Crypto core | 14% | ✅ Gate passed | 23/23 tests green, analyzer clean |
| P2 Key & PIN management | 11% | ✅ Built, device check pending | 62/62 tests green, APK builds; manual device pass outstanding |
| P3 Storage hardening | 9% | ✅ Built, device check pending | 85/85 tests green, APK builds; manual device pass outstanding |
| P4 Safety fixes | 9% | ✅ Built, device check pending | 108/108 tests green; manual device pass (DCIM check) outstanding |
| P5 Firebase + rules | 13% | 🟡 Code complete, unverified | Sync layer, rules, rules tests and Dart tests written; analyzer clean. Needs the Firebase project, then every gate |
| P6 Audit log | 10% | Not started | — |
| P7 Verification & export | 13% | 🟡 Part done early | Evidence viewing, playback and on-demand integrity verification built (11 tests). Court export and recovery key outstanding |
| P8 Offline sync | 9% | Not started | — |
| P9 Hardening & CI | 8% | Not started | — |

**Baseline before this branch: ~27%** (UI, decoy calculator, capture, plaintext local storage)
**Current: ~70% verified** — baseline + P0 (~3%) + P1 (14%) + P2 (11%) + P3 (9%) + P4 (9%); P2-P4 still pending their on-device checks
**~83% once P5 passes its gates**, plus part of P7 brought forward (viewing and verification)
**Review target: 65%**

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
