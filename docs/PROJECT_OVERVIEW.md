# Secure Evidence — what it does today, and what comes next

**Last updated:** 2026-09-23
**Branch:** `feature/p4-safety-fixes`
**Platform:** Android (Flutter 3.47.4 / Dart 3.13.3)
**Size:** 7,623 lines of Dart across 35 files, plus 2,579 lines of tests
**Test status:** 138 Dart tests passing · 15 Firebase security-rules tests passing

This document is the honest picture of the project: what is built and working,
what is built but switched off, and what is not built at all. Where something
does not work yet, it says so — a claim we cannot demonstrate is worth less than
no claim.

`DEVELOPMENT_CHECKLIST.md` holds the task-level detail. `docs/SECURITY.md` holds
the threat model and cryptographic design. This sits above both.

---

## 1. The problem

In domestic violence situations, evidence is fragile in a way most software
never considers. It is not only that photos and recordings can be lost — it is
that **having** them can itself be dangerous. An abuser who finds evidence on a
phone may destroy it, and may harm the person who collected it.

So the app has to do three things at once, and they pull against each other:

1. **Preserve** evidence so it survives and stays provably unaltered.
2. **Hide** that any evidence exists at all.
3. **Stay usable** by someone under stress, possibly in a hurry, possibly
   being watched.

Most of the design decisions in this project come from that third constraint
colliding with the first two.

---

## 2. What the app does today

### 2.1 It does not look like what it is

The app installs as **"Calculator"** and opens a fully working calculator:
addition, subtraction, multiplication, division, percentages, backspace,
divide-by-zero handling. Someone picking up the phone and opening it finds a
calculator, and can use it as one.

Entering a **secret sequence the user chose at setup** (for example `7×3-1=`)
opens a PIN screen. Anyone who does not know the sequence cannot reach it.

### 2.2 Getting in

| | |
|---|---|
| **First run** | The user chooses a 4-digit PIN and their own unlock sequence |
| **The PIN is never stored** | Not as text, not as a hash. A wrong PIN simply fails to unwrap the master key |
| **Key derivation** | PBKDF2-HMAC-SHA256, 150,000 iterations, random 128-bit salt, run off the UI thread |
| **Where the key lives** | Wrapped by the PIN-derived key, stored in Android Keystore-backed secure storage. Android cloud backup and device-to-device transfer are disabled |
| **Wrong PIN** | 4 free attempts, then 30s → 1m → 2m → 5m → 15m → 1h. Survives restarting the app, and the attempt is counted *before* the slow derivation runs |
| **No wipe** | Deliberately. Wiping after N failures would hand an abuser a way to destroy the evidence by typing wrong PINs |

### 2.3 Capturing evidence

Photo, video and audio capture happen **inside the app**. This matters more
than it sounds: the earlier version handed off to the system camera, which
leaves copies in the phone's gallery — the first place someone searching a
phone would look. The in-app camera writes only to app-private storage.

Anything a crash or a force-stop leaves behind is destroyed at the next launch.

### 2.4 How evidence is protected

Every captured file goes through the same sequence, and the order is chosen so
that the irreversible step happens last:

```
capture → encrypt → decrypt again and compare hashes → record in the index →
overwrite the original with zeros and delete it
```

If any step before the last fails, the original is kept and the partial
encrypted file is removed. Nothing is destroyed until there is a verified
replacement.

The cryptography:

| Purpose | Method |
|---|---|
| File encryption | **AES-256-GCM**, a fresh 256-bit key and 96-bit nonce per file |
| Key protection | **Envelope encryption** — each file key is wrapped by a master key, which is wrapped by the PIN-derived key |
| Evidentiary hash | **SHA-256**, streamed, so a 30-minute video never loads into memory |
| Tamper binding | The plaintext hash is bound into the encryption as **additional authenticated data**, so the file and its recorded hash cannot be swapped independently |

Changing the PIN re-wraps one 256-bit key. It does not re-encrypt a single
byte of evidence, so it is instant regardless of how much is stored.

On disk there is nothing to find: files are `<uuid>.enc` with no extension, and
the original filenames exist only inside an encrypted index.

### 2.5 The index, and why it has a seal

The list of evidence is itself encrypted, under a key derived separately from
the master key. Encryption detects any *edit* to that list. What it cannot
detect is someone restoring an **older, genuine** copy of it to hide everything
captured since.

So a seal — the item count plus a hash of the current index — is kept in
Keystore-backed storage and checked on every load. A rolled-back index is
caught and reported.

If the index cannot be trusted, the vault shows a **warning**, never
"No evidence yet". Telling a survivor her evidence is gone when it is still on
disk would be the most damaging thing this screen could do.

### 2.6 Viewing and verifying

Tapping an item opens it: photos with pinch-zoom, video and audio with
playback, alongside its metadata, encryption details and storage path.

**Verify Integrity** decrypts the evidence again, re-hashes what comes back,
and compares it against both the hash recorded at capture and the hash of the
stored file. The result screen shows every value it compared, so the verdict
can be read rather than taken on trust.

The decrypted copy exists only while the screen is open. It is destroyed when
the screen closes, when a panic or auto-lock tears the screen down, and again
at the next launch if the app was killed mid-view.

### 2.7 Safety features

| Feature | What happens |
|---|---|
| **Panic** | Hold anywhere for one second while unlocked. The master key is destroyed *before* anything redraws, every screen and dialog closes, and a fresh calculator appears reading `0`. Getting back in requires the PIN |
| **Auto-lock** | Locks when the app goes to the background. Ignores `inactive`, which also fires for permission pop-ups and the notification shade — locking there would throw the user out mid-task |
| **Recording protection** | A capture in progress defers auto-lock, so recording with the screen off works. Panic ignores this and discards the recording, because panic must be instant |
| **Screen privacy** | `FLAG_SECURE` blocks screenshots, screen recording and the thumbnail in the recent-apps list. The app's card in recents is blank |

### 2.8 The backend

Anonymous sign-in only: no email, no phone number. A confirmation message
would land in an inbox an abuser may be able to read.

For **every** capture, a small record goes to Firestore: the two hashes, the
wrapped key, a timestamp, a size, a type. No filename, no location, no free
text — nothing identifying, and nothing readable. The wrapped key is encrypted
under a master key that never leaves the phone, so to Firebase it is noise.

**The strongest property in the system**, and the one worth demonstrating:

```javascript
allow update, delete: if false;   // nobody, ever — including the owner
```

Once a record reaches the server it cannot be altered or removed. Not by an
abuser who seizes the phone, not by the survivor under coercion, not by us with
console access. The client cannot opt out, because the rule is evaluated
server-side. These rules are **deployed**, and 15 emulator tests prove each
refusal.

Nothing contacts Google until after the vault is unlocked. An app that phones
home the moment it opens is a signal in itself.

### 2.9 Built, but switched off

**Cloud backup of the encrypted files themselves.** The code, the rules and the
tests all exist. Firebase Storage is not enabled on the project — it requires a
billing account — so there is nowhere to put them.

The backup controls are still in the app. Tapping one explains that file copies
are not switched on yet, and what is and is not protected in the meantime. The
app knows up front and never attempts an upload that would fail slowly and
leave evidence wrongly badged as failed.

Turning it on later is one flag: enable Storage, deploy the storage rules, and
build with `--dart-define=CLOUD_BACKUP=true`.

So today the honest claim is the simple one: **no evidence media has ever left
the phone.** What the backend provides is *integrity and non-repudiation* —
proof that a file existed at a time and has not changed — not *preservation*.

---

## 3. What is not built

Stated plainly, because this is the list an examiner will ask about.

| Missing | Consequence |
|---|---|
| **Audit log** | No tamper-evident history of unlocks, captures, views and panics |
| **Court-export bundle** | No PDF manifest of hashes, timestamps and chain of custody to hand to a lawyer |
| **Recovery key** | A forgotten PIN means permanent loss. It also means a cloud backup could not be restored to a new phone even once Storage is on, because the master key and the anonymous account ID both live only on the one device |
| **Duress PIN** | No second PIN opening a decoy vault for when someone is forced to unlock |
| **Biometric unlock** | The settings toggle exists and does nothing |
| **Offline queue** | A metadata upload that fails is retried on the next vault visit, not queued with backoff |
| **Release signing** | Built with debug keys. Fine for a demo, not for distribution |
| **Launcher icon** | Labelled "Calculator" but still wearing the default Flutter logo, which undoes the disguise at a glance |
| **On-device testing** | **Everything above is proven by automated tests, not yet by a run on a real phone.** The DCIM check in particular — confirming photos never reach the gallery — is the single most important outstanding verification |

### Limits that are not bugs

- **A rooted phone defeats this.** Root can extract the wrapped key and try all
  10,000 PINs offline, and reset the lockout. Hardware-enforced attempt limits
  are not available to apps.
- **In-memory keys are extractable** while the app is unlocked, by an attacker
  with that level of access.
- **The app's presence is itself a signal.** The calculator defends against a
  casual look, not against someone who knows what to search for.
- **Metadata leaks a little.** File sizes, timestamps and counts are visible to
  the backend even though content is not.
- **No software can guarantee court admissibility.** That depends on
  jurisdiction, collection circumstances and evidence law.

---

## 4. Where the project stands

| Phase | Weight | Status |
|---|---|---|
| Baseline (UI, calculator, capture) | ~27% | Done before this work |
| P0 Planning & honest documentation | 4% | Done |
| P1 Crypto core | 14% | Done, 23 tests |
| P2 Key & PIN management | 11% | Done, 19 tests |
| P3 Encrypted storage | 9% | Done, 34 tests |
| P4 Safety & discretion | 9% | Done, 17 tests |
| P5 Backend & immutability | 13% | Done except blob upload; rules deployed, 15 rules tests |
| P6 Audit log | 10% | Not started |
| P7 Verification & export | 13% | Partly done early — viewing and integrity verification built |
| P8 Offline sync | 9% | Not started |
| P9 Hardening, duress PIN, CI | 8% | Not started |

**Roughly 80% complete**, against a review target of 65%.

---

## 5. Future scope

### 5.1 Next, in order

1. **On-device verification pass.** Everything in §2 confirmed on real
   hardware, especially that no capture reaches DCIM.
2. **Enable Firebase Storage** and flip the backup flag, so encrypted copies
   actually survive a lost phone.
3. **Tamper-evident audit log.** Append-only and hash-chained: each entry
   carries the hash of the previous one, so removing or altering any event
   breaks the chain visibly. Without chaining, an append-only log does not
   prove completeness.
4. **Recovery key.** A one-time printable code that wraps the master key, so a
   forgotten PIN is not permanent loss and a backup can be restored elsewhere.
   This is what makes "your evidence survives losing the phone" true.
5. **Court-export bundle.** The decrypted evidence plus a PDF manifest of
   hashes, timestamps and chain of custody — the form a lawyer can actually
   use.

### 5.2 Safety features worth building

- **Duress PIN** opening a decoy vault with innocuous content, for when someone
  is forced to unlock the app in front of another person.
- **Silent alert** — a trusted contact notified discreetly when panic is
  triggered, with no visible notification on the phone.
- **Scheduled check-ins**: if the user does not open the app for a set period,
  a nominated contact is told.
- **Stealth uninstall protection**, so evidence is not lost if the app is
  removed in anger.
- **Quick capture** from the calculator itself — a long-press that records
  audio without unlocking the vault first, for a situation escalating too fast
  to type a PIN.

### 5.3 Strengthening the evidence

- **Trusted timestamping** (RFC 3161) or anchoring hashes to a public ledger,
  so the time of capture is attested by someone other than us.
- **Capture-time context**: coarse location, device identity and a signed
  attestation that the photo came from this app's camera rather than being
  imported — which strengthens provenance considerably.
- **Play Integrity attestation**, so a record can show it came from a genuine,
  unmodified install.
- **Witness co-signing**, where a trusted third party countersigns the hash at
  capture time.

### 5.4 Reach and robustness

- **Offline upload queue** with exponential backoff.
- **Multi-device access** through the recovery key.
- **iOS support** — the code is Flutter, but the Keystore layer and
  `FLAG_SECURE` are Android-specific and need Keychain and screen-capture
  equivalents.
- **Localisation**, starting with Hindi and regional languages, since the
  helpline directory is already India-specific.
- **Accessibility**: screen-reader labels and large-text layouts.
- **CI** running the analyzer, the Dart tests and the rules tests on every push.
- **Proper release signing**, a real launcher icon, and a Play Store listing
  that does not give the app away.

### 5.5 Beyond the app

- **Direct handover to NGOs and legal aid**, so a survivor can share a verified
  bundle with a support organisation without the file passing through email.
- **Police and court integration** for jurisdictions that accept digital
  submissions.
- **Guided evidence collection**: prompts on what tends to matter in a case —
  dates, injuries, messages, witnesses — so evidence is useful as well as
  preserved.
- **An independent security review.** The design is documented openly for
  exactly this reason, and a system protecting people at this level of risk
  should be audited by someone who did not build it.

---

## 6. How to see it working

On a real Android phone, in the order that best shows what the project does:

1. First run → set a PIN and an unlock sequence → the calculator appears.
2. A wrong sequence does nothing; the right one opens the PIN screen; a wrong
   PIN starts the lockout countdown.
3. Capture a photo → open a file manager → **it is not in DCIM**.
4. `adb exec-out run-as <package> cat app_flutter/evidence/<uuid>.enc > blob.enc`
   → the file will not open in any viewer.
5. Open the item in the vault → it displays → **Verify Integrity** passes and
   shows every hash it compared.
6. Panic from the vault → an instantly cleared calculator; getting back in
   needs the PIN.
7. Background the app → auto-lock. Attempt a screenshot → blocked.
8. Firebase console → the record is there, carrying only hashes. **Then open the
   rules playground and attempt to delete or update it — both denied, even as
   the owner.**

**Lead with step 8.** Server-enforced immutability is the strongest claim this
project can make, and it is the one thing a marker cannot dismiss as UI.
