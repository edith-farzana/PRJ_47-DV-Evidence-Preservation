# 🛡️ Secure Evidence

### **When evidence matters, preserving it matters more.**

> A discreet digital space designed to help survivors of domestic violence **capture, preserve, and protect critical evidence** — without compromising their safety or privacy.

📸 Photos · 🎙️ Recordings · 💬 Digital Evidence · 🕒 Timestamps

---

## 🚧 Current Status

**This project is under active development — approximately 70% complete, with the backend written but not yet verified.**

This README describes the **design goals** of Secure Evidence. Sections below marked 🔴 are specified and planned but **not yet implemented**. We are documenting the target architecture openly rather than describing unbuilt features as if they shipped.

**Working today**
- ✅ Functional decoy calculator front-end with hidden unlock sequence
- ✅ User-chosen PIN and unlock sequence; the PIN unlocks a Keystore-protected master key, with persistent lockout (unit tested)
- ✅ In-app photo, video and audio capture — nothing is written to the device gallery
- ✅ Encrypted local evidence store: AES-256-GCM per file, encrypted index with rollback detection, plaintext source destroyed after a verified write
- ✅ Evidence vault, with playback and on-demand integrity verification; the decrypted copy is destroyed when the screen closes
- ✅ Panic (hold anywhere for a second), auto-lock on backgrounding, screenshots and the recents thumbnail blocked
- ✅ Emergency helpline directory

**Written, not yet verified**
- 🟡 Firebase backend with server-enforced immutability, and per-item opt-in cloud backup. The security rules and their emulator tests exist; nothing has run against a live project yet

**Not built**
- 🔴 Tamper-evident audit log
- 🔴 Court-export bundle and the recovery key that would let a backup be restored to a different phone

See **[`DEVELOPMENT_CHECKLIST.md`](DEVELOPMENT_CHECKLIST.md)** for the full build plan and **[`docs/SECURITY.md`](docs/SECURITY.md)** for the security design and threat model.

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

🔴 📋 **Traceability**  
Evidence-related information and events are structured to support accountability and verification.

🔴 ☁️ **Long-Term Preservation**  
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

🔴 **Auditability**  
Evidence-related actions can be recorded to provide a traceable history.

🟡 **Controlled Access**  
Access to preserved evidence is restricted through authentication and authorization.

🔴 **Preservation Controls**  
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

Security through obscurity protects nobody. The full cryptographic design, key hierarchy and threat model are published in **[`docs/SECURITY.md`](docs/SECURITY.md)**, including an honest account of what this system does *not* defend against. What stays private is the user's keys, which never leave their device — not the design that protects them.

---

## ⚡ Technology

### ✅ In use today

**Mobile**  
`Flutter` · `Dart` · `Android`

**Capture & storage**  
`camera` · `record` · `path_provider` · `video_player`

**Security**  
`AES-256-GCM` · `SHA-256` · `PBKDF2-HMAC-SHA256` · `Envelope Encryption` · `Android Keystore`

### 🟡 Written, not yet verified

**Backend**  
`Firebase Anonymous Auth` · `Cloud Firestore` · `Firebase Storage` · `Firestore Security Rules`

### 🔴 Planned

**Integrity**  
`Hash-chained audit log`

> **Note on the backend:** earlier drafts of this README described a custom `REST API` + `JWT` + `PostgreSQL` stack. We have since settled on **Firebase**, primarily because Firestore Security Rules let us enforce append-only, no-delete guarantees *server-side* — the client cannot opt out of them. Rationale is in [`docs/SECURITY.md`](docs/SECURITY.md).

> **Note on what leaves your device:** evidence **stays on your phone by default**. Only its cryptographic fingerprint and its encrypted key are recorded in the cloud — enough to prove the evidence existed and has not been altered, and not enough for anyone to view it. Uploading a copy of the file itself is a per-item choice you make. See [`docs/SECURITY.md` §3.3](docs/SECURITY.md).
>
> The trade-off is stated plainly in the app: an item kept only on your phone is **provably unaltered**, but does not survive losing the phone. An item you back up survives both.

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
