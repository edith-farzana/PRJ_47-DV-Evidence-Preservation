# 🛡️ Secure Evidence

### **When evidence matters, preserving it matters more.**

> A discreet digital space designed to help survivors of domestic violence **capture, preserve, and protect critical evidence** — without compromising their safety or privacy.

📸 Photos · 🎙️ Recordings · 💬 Digital Evidence · 🕒 Timestamps

---

## 🚧 Current Status

**This project is under active development — approximately 95% complete.** Everything below is covered by automated tests (207 app tests, 15 server-rule tests); the full on-device test pass is still outstanding.

This README describes the **design goals** of Secure Evidence. Sections below marked 🔴 are specified and planned but **not yet implemented**. We are documenting the target architecture openly rather than describing unbuilt features as if they shipped.

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
- ✅ Firebase backend with **server-enforced immutability**: every capture's fingerprint is recorded in Firestore, where update and delete are denied to everyone — including the account that created it. Rules deployed and covered by 15 emulator tests

**Built, but switched off**
- 🟡 Per-item opt-in cloud backup of the encrypted files. Firebase Storage needs a billing account we have not added, so the app says so plainly rather than failing. Evidence media leaves the phone only when she exports it

**Not built**
- 🔴 The recovery key, which would make a forgotten PIN recoverable and let a backup be restored to a different phone
- 🔴 Duress PIN, biometric unlock, and release signing (builds are currently signed with debug keys)

**[`docs/HOW_IT_WORKS.md`](docs/HOW_IT_WORKS.md)** walks through every flow in plain language, including what the app does when someone interferes and what it cannot defend against. **[`DEVELOPMENT_CHECKLIST.md`](DEVELOPMENT_CHECKLIST.md)** has the full build plan and history.

---

## 🔐 Why Secure Evidence?

In domestic violence situations, evidence can be lost, discovered, altered, or deleted long before it reaches a courtroom.

**Secure Evidence is designed around one core idea:**

### **Preserve the evidence. Protect its integrity. Protect the survivor.**

✅ 🕵️ **Discreet by Design**  
A familiar interface helps keep the purpose of the application private.

✅ 📸 **Evidence Preservation**  
Sensitive evidence can be captured and preserved within a protected environment.

✅ 🔒 **Layered Security**  
Evidence is protected through a purpose-built encryption and integrity architecture.

✅ 🧬 **Evidence Integrity**  
The system is designed to help establish that preserved evidence has not been silently altered.

✅ 📋 **Traceability**  
Evidence-related information and events are structured to support accountability and verification.

🟡 ☁️ **Long-Term Preservation**  
Designed for secure storage, synchronization and resilient evidence preservation.

✅ 🚨 **Panic Protection**  
A rapid return to the discreet interface when immediate privacy is required.

---

## ⚖️ Built With Evidentiary Integrity in Mind

Digital evidence is only useful when its **authenticity, integrity, provenance, and preservation** can be reasonably demonstrated.

Secure Evidence is designed to support these principles through:

✅ **Protected Evidence**  
Sensitive content is secured through a layered encryption architecture.

✅ **Time & Metadata**  
Relevant evidence information is preserved alongside the captured material.

✅ **Integrity Verification**  
Cryptographic mechanisms are designed to detect unauthorized alteration.

✅ **Auditability**  
Evidence-related actions can be recorded to provide a traceable history.

✅ **Controlled Access**  
Access to preserved evidence is restricted through authentication and authorization.

✅ **Preservation Controls**  
The architecture is designed to reduce unauthorized modification or deletion at the storage and backend layers.

> **The objective is not simply to store evidence — but to preserve its integrity and history.**

---

## 🧠 The Idea

A normal storage application thinks:

**Capture → Store → View**

Secure Evidence thinks:

### **Capture → Protect → Preserve → Verify**

The difference is the entire idea.

---

## 🛡️ Security, Without Exposing the Evidence

The underlying security architecture combines modern cryptographic protection, integrity verification, controlled access, secure storage and key-management principles.

The implementation is intentionally designed so that **the evidence itself remains protected throughout its lifecycle.**

### The design is documented openly — the keys are not.

Security through obscurity protects nobody. How the protection works, and an honest account of what this system does *not* defend against, are written up in **[`docs/HOW_IT_WORKS.md`](docs/HOW_IT_WORKS.md)**. What stays private is the user's keys, which never leave their device — not the design that protects them.

---

## ⚡ Technology

### ✅ In use today

**Mobile**  
`Flutter` · `Dart` · `Android`

**Capture & storage**  
`camera` · `record` · `path_provider` · `video_player`

**Security**  
`AES-256-GCM` · `SHA-256` · `PBKDF2-HMAC-SHA256` · `Envelope Encryption` · `Android Keystore`

**Backend**  
`Firebase Anonymous Auth` · `Cloud Firestore` · `Firestore Security Rules`

### 🟡 Built, switched off

**Cloud file backup**  
`Firebase Storage`

**Integrity**  
`Hash-chained activity log` · `Keystore-sealed rollback detection`

> **Note on the backend:** earlier drafts of this README described a custom `REST API` + `JWT` + `PostgreSQL` stack. We have since settled on **Firebase**, primarily because Firestore Security Rules let us enforce append-only, no-delete guarantees *server-side* — the client cannot opt out of them.

> **Note on what leaves your device:** only each item's cryptographic fingerprint and its encrypted key are recorded in the cloud — enough to prove the evidence existed and has not been altered, and not enough for anyone to view it. **Evidence media leaves the phone only when she exports it herself**, in a bundle that is password-protected by default.
>
> The trade-off is stated plainly in the app: evidence is **provably unaltered**, but does not survive losing the phone. Uploading an encrypted copy is built as a per-item choice but switched off for now. Even once it is on, restoring a backup to a *different* phone needs the recovery key, which is not built yet — until then a backup can only be reopened on the phone that made it.


### Building it yourself

The Firebase project's configuration files — `android/app/google-services.json` and `lib/firebase_options.dart` — are deliberately **not** in this repository. A fresh clone therefore needs them generated before it will build:

```bash
flutterfire configure
```

Choose the Firebase project and **Android** only. Then `flutter build apk`. Without that step the Android build stops at the Google Services plugin.

---

## ⚖️ Legal & Evidentiary Considerations

Secure Evidence is designed with digital-evidence preservation principles in mind, including:

- **Integrity**
- **Authenticity**
- **Provenance**
- **Timestamping**
- **Controlled access**
- **Auditability**
- **Secure preservation**
- **Protection against unauthorized alteration**

These mechanisms are intended to help maintain the reliability and evidentiary value of preserved digital records.

### Important

**No software can independently guarantee that evidence will be admitted by a court.**

Admissibility depends on the applicable jurisdiction, court, collection circumstances, applicable evidence laws, chain-of-custody requirements, and other legal considerations.

Secure Evidence is designed to **support those requirements through stronger preservation and integrity controls**, rather than claiming to determine legal admissibility itself.

---

## 🌍 More Than an App

Domestic violence can create situations where even **having evidence can become a safety risk.**

That's why privacy, discretion and preservation are treated as part of the same problem.

### **🔐 Protect the evidence.**
### **🛡️ Preserve its integrity.**
### **❤️ Protect the person behind it.**

---

<p align="center">

### **SECURE EVIDENCE**

*Because some evidence is too important to lose.*

</p>
