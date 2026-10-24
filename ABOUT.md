# About Secure Evidence

### **Preserve the evidence. Protect its integrity. Protect the survivor.**

This document is the whole picture: how the idea came about, the problem we are trying to solve, how the app solves it, what is built today, and how it works underneath. To set the project up, start with the **[README](README.md)**. For a step-by-step walk-through of every flow in plain language, read **[docs/HOW_IT_WORKS.md](docs/HOW_IT_WORKS.md)**.

**Contents**

1. [How the idea came about](#-how-the-idea-came-about)
2. [The problem](#-the-problem)
3. [How Secure Evidence solves it](#-how-secure-evidence-solves-it)
4. [What works today](#-what-works-today)
5. [Built with evidentiary integrity in mind](#%EF%B8%8F-built-with-evidentiary-integrity-in-mind)
6. [Technical design](#%EF%B8%8F-technical-design)
7. [What it cannot do](#-what-it-cannot-do)
8. [Legal and evidentiary considerations](#%EF%B8%8F-legal-and-evidentiary-considerations)
9. [Sources](#-sources)

---

## 💡 How the idea came about

It started with a question, not an app. We wanted to build something that mattered, so we went looking for problems in India that do real damage to people's lives, the kind technology might actually help with. We searched, read reports and surveys, and kept a list.

Domestic violence kept coming back to the top of that list, and the numbers would not let us move on.

**It is common.** In India's fifth National Family Health Survey (NFHS-5, 2019–21), 32% of ever-married women reported emotional, physical or sexual violence from their husbands. That is roughly one in three. The same survey found that over 45% of women believe a husband is right to beat or harass his wife in some situations, such as when she neglects the housework or argues with him.[^1]

**Most of it is never reported.** Of the women in NFHS-5 who had faced violence from a partner, only 14.2% had sought help from anyone at all,[^2] whether the police, a doctor or even their own family. Reporting on the survey found that 77% had never sought help *or* told a single person.[^3] We had read that 85 to 90% of cases never reach an FIR. The survey data is starker still: about 86 in every 100 women never ask anyone for help in the first place.

**What does get reported is still enormous.** Even so, "cruelty by husband or his relatives" was the largest category of crime against women registered by police in 2024: 1,20,227 cases. That is more than one in four of all crimes against women, about one every four minutes.[^4] Every one of those is a woman who made it as far as an FIR.

**And then it waits.** In February 2023 the Supreme Court pointed to a study by the National Legal Services Authority showing that more than 4.71 lakh cases under the Protection of Women from Domestic Violence Act were pending across the country as of July 2022.[^5] A case that waits years needs evidence that survives years, and that can still be shown to be untouched when it is finally heard.

Reading those numbers side by side, we kept picturing the same person: a woman being hurt today who might, one day, be ready to go to the police or a court. What would she need on that day? Proof. Photos of injuries, a recording of a threat, the date it happened.

But collecting that proof now is dangerous. The phone she would use is often the first place her abuser looks. A photo sitting in her gallery is evidence and a risk at the same time. And if she does manage to keep it safe for years, will anyone believe it has not been edited?

That last question turned out to be one India's own evidence law asks. Under the Bharatiya Sakshya Adhiniyam, 2023, electronic evidence goes to court with a certificate, and the form in the Act's Schedule asks for the file's **hash value** and the algorithm used to calculate it, with SHA-256 among the options.[^6] A fingerprint taken at the moment of capture, and kept somewhere nobody can change it, is exactly what that question needs.

That was when the app took shape. It would be something that:

- **looks like nothing**, so having it on the phone is not a risk;
- **keeps the evidence locked**, so finding the phone is not enough; and
- **proves the evidence is untouched**, so years of waiting do not weaken it.

Hidden, protected and provable. Secure Evidence is our attempt to build exactly that.

---

## 🎯 The problem

A woman experiencing domestic violence photographs her injuries. That photo is now two things at once: **evidence that could help her in court**, and **a danger to her if the wrong person finds it on her phone**.

Ordinary apps solve only half of this:

- A **gallery app** keeps the photo, but anyone who picks up the phone can see it.
- A **hidden-vault app** hides it, but cannot prove months later in a courtroom that it is genuine.
- **Neither survives** the moment an abuser takes the phone and deletes everything.

In domestic violence, evidence can be lost, discovered, altered or deleted long before it reaches a courtroom. Even *having* evidence can be a safety risk. Privacy, discretion and preservation are not three separate features here; they are one problem.

---

## 🧩 How Secure Evidence solves it

A normal storage app thinks **Capture → Store → View**. Secure Evidence thinks:

### **Capture → Protect → Preserve → Verify**

| Goal | How |
|---|---|
| **Hide it** | The app looks and works like a calculator. The evidence is not visible anywhere on the phone |
| **Protect it** | Every file is encrypted. Without the user's PIN, the files are meaningless noise |
| **Prove it** | Each file gets a unique fingerprint, stored on a server where **nobody can change or delete it, not even us** |

In everyday terms:

- 🕵️ **The disguise.** It is a working calculator, not a fake one: you can add up a shopping bill on it. It installs as "Calculator" with a calculator icon. The evidence side opens only when you type a secret sum you chose yourself, such as `7×3-1=`.
- 🔐 **The lock.** A PIN opens the vault. The PIN is never stored anywhere; it is used to rebuild the key, so there is nothing on the phone to steal or crack. Wrong guesses make an attacker wait longer and longer, up to an hour, and the evidence is never wiped. Wiping it would hand an abuser an easy way to destroy it.
- 📸 **Capture without a trace.** Photos, video and audio are captured inside the app. Nothing ever lands in the phone's gallery.
- 🧬 **The fingerprint.** Each capture gets a SHA-256 fingerprint: a 64-character code that changes completely if even one pixel changes. It is recorded on the phone and on a server that refuses all edits and deletions.
- ✅ **Verify.** One tap re-checks a file against four fingerprints, including the server's, and says plainly whether it is untouched.
- 🚨 **Panic.** Hold a finger anywhere on the screen for one second and the app is instantly a calculator again, showing `0`.
- 📋 **The activity log.** Every unlock, wrong PIN, panic, capture and view is recorded in a chain that shows if anyone edits or deletes an entry. If someone tried her PIN while she was away, she is told the next time she opens the app.
- ⚖️ **Export for a lawyer.** Chosen evidence goes out in one password-protected bundle, with a PDF listing every file's fingerprint and history, so anyone can check it with tools already on their computer.

**[docs/HOW_IT_WORKS.md](docs/HOW_IT_WORKS.md)** explains each of these step by step, including every "what if" we could think of.

---

## ✅ What works today

The project is under active development, about **95% complete**. Everything below is covered by automated tests (220 app tests, 15 server-rule tests); the full on-device test pass is still outstanding.

**Working today**
- ✅ Functional decoy calculator front-end with hidden unlock sequence. Installs as **"Calculator"** with a calculator icon, so nothing in the app drawer gives it away
- ✅ User-chosen PIN and unlock sequence; the PIN unlocks a Keystore-protected master key, with persistent lockout (unit tested)
- ✅ In-app photo, video and audio capture — nothing is written to the device gallery
- ✅ Encrypted local evidence store: AES-256-GCM per file, encrypted index with rollback detection, plaintext source destroyed after a verified write
- ✅ Evidence vault, with playback and on-demand integrity verification — checked against the phone's own records **and** against the server's, which nobody can alter. The decrypted copy is destroyed when the screen closes
- ✅ Panic (hold anywhere for a second), auto-lock on backgrounding, screenshots and the recents thumbnail blocked
- ✅ Emergency helpline directory
- ✅ **Court-export bundle**: chosen evidence plus a PDF manifest of fingerprints, verification results and custody history, and instructions anyone can follow to check it with standard tools. AES-256 password-protected by default; only verified items leave; nothing decrypted is left on the phone
- ✅ Tamper-evident **activity log**: every unlock, wrong PIN, panic, capture and view, hash-chained so any edit, deletion or rollback shows. Wrong PINs entered while she was away are shown to her at the next unlock — until now they left no trace once the right PIN went in
- ✅ Firebase backend with **server-enforced immutability**: every capture's fingerprint is recorded in Firestore straight after capture (or at the next unlock, if the phone was offline), where update and delete are denied to everyone — including the account that created it. Rules deployed and covered by 15 emulator tests

**Built, but switched off**
- 🟡 Per-item opt-in cloud backup of the encrypted files. Firebase Storage needs a billing account we have not added, so the app says so plainly rather than failing. Evidence media leaves the phone only when she exports it

**Not built**
- 🔴 The recovery key, which would make a forgotten PIN recoverable and let a backup be restored to a different phone
- 🔴 Duress PIN, biometric unlock, and release signing (builds are currently signed with debug keys)

**[DEVELOPMENT_CHECKLIST.md](DEVELOPMENT_CHECKLIST.md)** has the full build plan, phase by phase.

---

## ⚖️ Built with evidentiary integrity in mind

Digital evidence is only useful when its **authenticity, integrity, provenance and preservation** can be reasonably demonstrated. Secure Evidence supports those principles through:

- ✅ **Protected evidence**: every file is encrypted with its own key, inside a layered key design.
- ✅ **Time and metadata**: the capture time, size and fingerprints are kept alongside each item.
- ✅ **Integrity verification**: the four-fingerprint check detects any alteration, on the phone or against the server.
- ✅ **Auditability**: the hash-chained activity log records what happened to the evidence, and when.
- ✅ **Controlled access**: the vault opens only with the secret sequence and the PIN, and the server accepts records only from the account that made them.
- ✅ **Preservation controls**: the server forbids changing or deleting a record, for every account, including ours.
- 🟡 **Long-term preservation**: encrypted cloud backup is built but switched off until Firebase Storage is enabled.

> **The objective is not simply to store evidence, but to preserve its integrity and its history.**

---

## 🛠️ Technical design

### The design is documented openly; the keys are not

Security through obscurity protects nobody. How the protection works, and an honest account of what it does *not* defend against, are written up here and in **[docs/HOW_IT_WORKS.md](docs/HOW_IT_WORKS.md)**. What stays private is each user's keys, which never leave their phone.

### Keys and encryption

```text
PIN ─▶ PBKDF2-HMAC-SHA256 (150,000 iterations) ─▶ PIN-derived key
                                                        │ unwraps
                                                        ▼
                                  master key (stored encrypted under a
                                  non-exportable Android Keystore key)
                                                        │ wraps
                                                        ▼
                                  a fresh data key for every file ─▶ AES-256-GCM
```

- **The PIN is never stored or compared.** A wrong PIN simply fails to unwrap the master key. The deliberately slow key derivation (about a second) makes guessing impractical, and a persistent lockout makes the attacker wait between guesses.
- **Envelope encryption.** Each file is encrypted with its own random 256-bit key, and only that small key is wrapped under the master key. Changing the PIN re-wraps one key, not every file, so it is instant.
- **The fingerprint is bound into the encryption.** Each file's SHA-256 is used as AES-GCM authenticated data. Change the recorded fingerprint to match a substitute photo, and the file stops decrypting altogether.

### What happens at capture

1. **Encrypt** the file with a fresh key.
2. **Fingerprint** the original with SHA-256.
3. **Check the work**: decrypt the new file and confirm it reproduces the original exactly.
4. **Record it** in the encrypted index.
5. **Destroy the original**: overwrite it with zeros and delete it. Only now, because nothing is destroyed before a verified replacement exists.
6. **Send the server record** in the background, without delaying the save.

The index is itself encrypted and sealed with a record kept in the Keystore, so restoring an older copy of it, which would hide recent captures, is detected.

### The server record

- **Firebase Anonymous Auth**: each phone gets an ID with no email or phone number attached, because a confirmation email or SMS could land somewhere an abuser can read.
- **Cloud Firestore**, at `users/{uid}/evidence/{evidenceId}`, holds the fingerprints, the capture date, the file size and the locked file key. That is enough to prove the evidence existed and is unaltered, and not enough to view it.
- **Security rules** allow the owner to create and read a record, and deny `update` and `delete` to everyone, including the owner and the project's administrators. The rules are covered by 15 emulator tests.
- **When it is sent**: straight after capture; if there is no signal, at the next unlock; and whenever the vault opens, until the server has it. Nothing is sent while the app is still a calculator, and panic and auto-lock never wait on the network.

### Verification: four fingerprints, three verdicts

| Fingerprint | Where it comes from |
|---|---|
| **Recorded** | Taken at capture, read from the encrypted index |
| **Recalculated** | Computed fresh from the file decrypted right now |
| **Stored file** | Computed fresh from the encrypted file on disk |
| **Server record** | Fetched from the server, the one copy nobody can change |

The result is **INTEGRITY VERIFIED** (everything matches, and the server agrees), **VERIFIED ON THIS PHONE** (the phone's checks pass, but the server could not be asked), or **INTEGRITY NOT VERIFIED** (something disagrees; never softened). Even someone with the phone *and* the PIN, who swaps a file together with its entry in the index, is caught, because the server record does not match.

### The activity log, panic and screen privacy

- **Activity log**: each entry carries the fingerprint of the one before it, so editing, deleting or truncating entries breaks the chain, and a seal in the Keystore catches a rolled-back copy. It is encrypted and stays on the phone.
- **Panic**: a one-second hold anywhere wipes the key from memory first, closes every screen and shows a fresh calculator.
- **Auto-lock**: the app locks and forgets the key when it goes to the background, except while a recording is in progress.
- **Screen privacy**: `FLAG_SECURE` blocks screenshots, screen recording, casting and the recent-apps preview.

### The court-export bundle

A ZIP holding the chosen evidence (decrypted), `manifest.pdf` and `manifest.json` listing each item's fingerprints, verification result and history, and a `README.txt` explaining how to check it. Every item is verified again before it goes in; one that fails is left out and listed with the reason. The bundle is AES-256 password-protected by default, with a generated 20-character password to pass on separately. All names inside are neutral, and nothing decrypted is left on the phone afterwards. Anyone can check the files with `shasum -a 256` on a Mac or `certutil -hashfile … SHA256` on Windows.

### What leaves the phone

Only each item's fingerprints, date, size and locked key, which is enough to prove the evidence existed and has not been altered, and not enough for anyone to view it. **Evidence media leaves the phone only when she exports it herself**, in a bundle that is password-protected by default.

The trade-off is stated plainly in the app: evidence is **provably unaltered**, but does not survive losing the phone. Uploading an encrypted copy is built as a per-item choice but switched off for now. Even once it is on, restoring a backup to a *different* phone needs the recovery key, which is not built yet; until then, a backup can only be reopened on the phone that made it.

### Technology

**In use today**

- **Mobile**: `Flutter` · `Dart` · `Android`
- **Capture and storage**: `camera` · `record` · `path_provider` · `video_player`
- **Security**: `AES-256-GCM` · `SHA-256` · `PBKDF2-HMAC-SHA256` · `Envelope encryption` · `Android Keystore`
- **Integrity**: `Hash-chained activity log` · `Keystore-sealed rollback detection`
- **Backend**: `Firebase Anonymous Auth` · `Cloud Firestore` · `Firestore Security Rules`
- **Export**: `pdf` · `archive` (AES-256 ZIP) · `share_plus`

**Built, switched off**

- **Cloud file backup**: `Firebase Storage`

> **Why Firebase:** early drafts of this project described a custom `REST API` + `JWT` + `PostgreSQL` stack. We settled on Firebase mainly because Firestore Security Rules enforce the append-only, no-delete guarantee *on the server*, where the app cannot opt out of it.

### Where things live in the code

| Path | What it holds |
|---|---|
| `lib/features/calculator/` | The decoy calculator and the hidden unlock sequence |
| `lib/features/auth/` | First-run setup, the PIN screen and changing the PIN |
| `lib/features/home/`, `lib/features/vault/` | The evidence center and the evidence list |
| `lib/features/evidence/` | In-app capture, the detail screen and integrity verification |
| `lib/features/audit/`, `lib/features/export/` | The activity log screen and export for a lawyer |
| `lib/services/crypto/` | Key derivation, the Keystore-backed key store and per-file encryption |
| `lib/services/storage/` | The encrypted file store, the sealed index and secure deletion |
| `lib/services/sync/` | The server record, sent at capture and at unlock |
| `lib/services/audit/`, `lib/services/export/` | The hash-chained log and the court-export bundle |
| `firestore.rules`, `storage.rules` | The server rules that make records unchangeable |
| `test/`, `test/rules/` | The app tests and the emulator-backed rules tests |

---

## 🚧 What it cannot do

A system that claims no weaknesses is not credible. The honest list:

- **It cannot guarantee a court will admit the evidence.** That depends on the jurisdiction, how the evidence was collected, and the law.
- **It cannot protect against a compromised phone.** A keylogger captures the PIN as it is typed, and an attacker with root access can break the protection.
- **It cannot hide that the app exists** from someone who knows what to look for.
- **It cannot help if she is forced to unlock it**, until the planned duress PIN is built.
- **A phone kept offline from the moment of capture** has no server record yet, so verification can only say VERIFIED ON THIS PHONE.
- **A forgotten PIN means the evidence cannot be recovered**, by anyone, until the recovery key is built. The app warns about this at setup.

**[docs/HOW_IT_WORKS.md](docs/HOW_IT_WORKS.md)** goes through each of these, and every other "what if", in detail.

---

## ⚖️ Legal and evidentiary considerations

Secure Evidence is designed with digital-evidence preservation principles in mind: integrity, authenticity, provenance, timestamping, controlled access, auditability, secure preservation and protection against unauthorised alteration. These are intended to help maintain the reliability and evidentiary value of preserved digital records.

In India, electronic evidence is admitted under Section 63 of the Bharatiya Sakshya Adhiniyam, 2023, with a certificate in the form set out in the Act's Schedule, which asks for the record's hash value.[^6] The SHA-256 fingerprints the app records at capture, keeps on the server and lists in every export manifest are that kind of value. The app does not produce the certificate itself.

**No software can independently guarantee that evidence will be admitted by a court.** Admissibility depends on the jurisdiction, the court, how the evidence was collected, the applicable evidence law, chain-of-custody requirements and other legal considerations. Secure Evidence is designed to **support those requirements through stronger preservation and integrity controls**, not to decide admissibility.

---

## 🌍 More than an app

Domestic violence can create situations where even **having evidence becomes a safety risk**. That is why privacy, discretion and preservation are treated as one problem here.

### **🔐 Protect the evidence.**
### **🛡️ Preserve its integrity.**
### **❤️ Protect the person behind it.**

---

## 📎 Sources

[^1]: Holla R, Sreedevi SR, Rao M, Jose J. "Domestic Violence – Are Women Safe Now? A Comparison between Nationwide Surveys of India". *Journal of Mid-Life Health*, 2026, citing NFHS-5. https://pmc.ncbi.nlm.nih.gov/articles/PMC13160540/

[^2]: Ghoshal R, et al. "Factors associated with help-seeking by women facing intimate partner violence in India: findings from National Family Health Survey-5 (2019–2021)". *BMC Global and Public Health*, 2024. https://link.springer.com/article/10.1186/s44263-024-00056-3

[^3]: "77% of women stay mum about domestic violence". *The Times of India*, reporting NFHS-5. https://timesofindia.indiatimes.com/india/77-of-women-stay-mum-about-domestic-violence/articleshow/91408159.cms

[^4]: Thomas S. "What India's 2024 crime statistics reveal (and miss) about violence against women". CEDA, Ashoka University, June 2026, on NCRB *Crime in India 2024*. https://ceda.ashoka.edu.in/what-indias-2024-crime-statistics-reveal-and-miss-about-violence-against-women/

[^5]: "Look into 4L pending domestic violence cases, SC tells Centre". *The Tribune*, 26 February 2023. https://www.tribuneindia.com/news/nation/look-into-4l-pending-domestic-violence-cases-sc-tells-centre-483143

[^6]: The Bharatiya Sakshya Adhiniyam, 2023, Section 63(4) and the Schedule. Text of the Act published by the High Court of Tripura: https://thc.nic.in/Central%20Governmental%20Acts/Bharatiya%20Sakshya%20Adhiniyam,%202023.pdf. Section 63: https://indiankanoon.org/doc/125020475/

---

### **SECURE EVIDENCE**

*Because some evidence is too important to lose.*
