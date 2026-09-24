# How Secure Evidence Works

**A complete walk-through, in plain language**

**Last updated:** 2026-09-24

---

## Who this is for

This document explains everything the app does, step by step, without assuming
any technical background. Where a technical term is unavoidable it is explained
the first time it appears, and there is a glossary at the end.

If you want the task-level detail and build history instead,
`DEVELOPMENT_CHECKLIST.md` has it.

---

## The idea in one page

A woman experiencing domestic violence photographs her injuries. That photo is
now two things at once: it is **evidence that could help her in court**, and it
is **a danger to her if the wrong person finds it on her phone.**

Ordinary apps solve only half of this. A gallery app keeps the photo but
announces it. A hidden-vault app hides it but cannot prove it is genuine months
later in a courtroom. And neither survives the moment an abuser takes the phone
and deletes everything.

Secure Evidence tries to do all three:

| Goal | How |
|---|---|
| **Hide it** | The app looks and works like a calculator. The evidence is not visible anywhere on the phone |
| **Protect it** | Every file is scrambled with military-grade encryption. Without the user's PIN, the files are meaningless noise |
| **Prove it** | Each file gets a unique fingerprint, stored on a server where **nobody can change or delete it — not even us** |

That third one is the part that is genuinely unusual, and it is the subject of
most of this document.

---

## Part 1: The pieces, explained

Six ideas make up the whole system. Everything else is detail.

### The disguise

The app is a working calculator. Not a fake one — it does real arithmetic, and
someone can use it to add up a shopping bill. There is no hidden button, no
long-press, nothing to notice. The evidence side opens only when the user types
a **secret sequence they chose themselves** — something like `7×3-1=`.

### The lock

The user's PIN. Here is the unusual part: **the PIN is not stored anywhere.**
Not written down, not even scrambled and written down.

Instead, the PIN is used as an ingredient to *reconstruct* the key that opens
the evidence. Type the right PIN and the key comes out correctly. Type a wrong
one and you get a different key, which simply fails to open anything. There is
nothing on the phone to steal, compare against, or crack.

### The safe

Every piece of evidence is encrypted — scrambled into meaningless data — using
**AES-256**, the same standard used by banks and governments. The scrambled
files sit in the app's private folder with names like
`a7f3e891-4c2b.enc`. Nothing in the name says whether it is a photo, a video or
a recording, or when it was taken.

If someone copies that file off the phone and opens it, they see nothing. Not a
blurry photo. Not a corrupted photo. Random noise.

### The fingerprint

**This is the most important idea in the document, and the one that answers
"how do we know it wasn't tampered with".**

When a photo is captured, the app calculates a **SHA-256 fingerprint** of it —
a 64-character code like:

```
e2cd419d25fcdf811bfaf5da1c1093f13041a6adab59c7fc171c3bac5803f5e4
```

Three things make this useful:

1. **The same file always produces the same fingerprint.** Every time, on any
   device, forever.
2. **Any change produces a completely different one.** Not a slightly different
   one — change a single pixel, or one bit in an audio recording, and the
   fingerprint is unrecognisably different.
3. **You cannot work backwards.** The fingerprint reveals nothing about the
   photo. You cannot reconstruct the image from it, or even tell whether it was
   a photo or a recording.

So the fingerprint is safe to store publicly, and it is proof of exactly one
thing: **this file, and no other file, is the one that was captured.**

> **A common misunderstanding worth clearing up:** the fingerprint is not a
> password or an encryption key. Nothing is unlocked with it, and it cannot
> decrypt anything. It is closer to a tamper-evident seal — useful only for
> checking whether something changed.

### The logbook

The list of what evidence exists — filenames, dates, sizes, fingerprints — is
itself encrypted. And it carries a **seal**: a record of how many items it
should contain and what the list itself should look like.

This catches an attack that encryption alone misses. Suppose someone cannot
edit the list, but they saved a copy of it last week and put that old copy back
today. Every item in it is genuine; it is just missing everything captured
since. The seal catches exactly this, because the old copy does not match the
seal.

### The notary

When evidence is captured, a small record is sent to a server (Google's
Firebase): the fingerprint, the date, the file size. **No filename, no
location, no photo, nothing identifying.**

That record is written under a rule that **forbids anyone from ever changing or
deleting it** — including the account that created it, and including us as the
developers. The rule lives on the server, so the app cannot bypass it even if
someone modified the app.

This is what turns the fingerprint into proof. A fingerprint sitting only on
the survivor's phone proves little — she could have created it at any time. A
fingerprint recorded on an independent server, at a timestamp nobody can move,
is a much stronger thing to bring to a court.

---

## Part 2: Every action, step by step

### Opening the app for the first time

1. The app asks for a **4-digit PIN**, twice, to catch typing mistakes.
2. It asks the user to choose a **secret unlock sequence** — the calculator
   keys that will open the evidence side. It must contain an operator, so that
   ordinary arithmetic can never trigger it by accident.
3. It warns, clearly, that **a forgotten PIN means the evidence cannot be
   recovered by anyone.** This is a consequence of the security, not an
   oversight: if we could recover it, so could someone else.
4. Behind the scenes it creates the master key that everything will be
   protected with, locks it with the PIN, and stores it in the phone's hardware
   security chip.

From then on, the app opens as a calculator.

### Opening it on any normal day

1. The calculator appears. Use it as a calculator and nothing else happens.
2. Type the secret sequence. The PIN screen appears.
3. Enter the PIN. The app spends about a second deliberately grinding through a
   slow calculation — this is intentional, and it is what makes guessing PINs
   impractical.
4. The evidence side opens.

### If the PIN is wrong

Four attempts are free. After that the app makes the attacker wait, and the
wait grows: **30 seconds, then 1 minute, 2, 5, 15, and an hour.**

Three details matter here:

- The wait **survives restarting the app**, or the phone. Killing the app does
  not reset it.
- The attempt is counted **before** the slow calculation runs, so force-quitting
  mid-guess does not buy a free attempt.
- **The app never erases the evidence after repeated wrong PINs.** Many secure
  apps do. Here it would be a gift to an abuser: he could destroy everything
  just by typing wrong PINs at her phone. Locking him out is enough.
- **She is told.** The moment the right PIN goes in, the count of wrong ones
  resets — so without anything more, three wrong guesses made while she was
  away would leave no trace at all. Instead, each one is recorded as it
  happens, and the next time she opens the app she sees a short notice: how
  many wrong PINs, and when. It allows for her own typos ("if that wasn't
  you…"), because the aim is that she knows, not that she is alarmed by a
  false alarm.

### Capturing evidence

Photos, video and audio are all captured **inside the app**, using its own
camera screen.

This is not a cosmetic choice. An earlier version of this app opened the phone's
normal camera app, which leaves a copy in the phone's photo gallery — the very
first place someone going through a phone would look. That was one of the most
serious problems found in this project, and fixing it was a priority.

### What happens to a photo the moment it is taken

This is the most carefully designed sequence in the app, because one of the
steps cannot be undone. In order:

1. **Encrypt.** The photo is scrambled into an unreadable file, using a key
   generated fresh for this one file.
2. **Calculate the fingerprint** of the original photo.
3. **Check the work.** The app immediately decrypts the file it just created
   and confirms it produces exactly the original photo again.
4. **Record it** in the encrypted list.
5. **Destroy the original.** Only now. The original is overwritten with zeros
   and deleted.

**If anything in steps 1 to 4 fails, the original photo is kept and the partial
encrypted file is thrown away.** Nothing is destroyed until there is a verified
replacement. It is the same instinct as not shredding a document until you have
confirmed the photocopy came out.

A reviewer may reasonably ask: why bother with step 3, when step 1 just
succeeded? Because "the encryption function returned without an error" and
"this file can actually be recovered" are different claims, and only the second
one matters when the original is about to be destroyed.

### Where the fingerprint is kept

The fingerprint from step 2 is stored in **three places**, deliberately:

| Where | Why there |
|---|---|
| In the **encrypted list** on the phone | So the app can check the file later without a network connection |
| **Welded into the encrypted file itself** | Explained below — this is the clever part |
| On the **server**, in the record nobody can alter | So the proof survives even if the phone does not |

That second one deserves explanation. The fingerprint is not merely stored
*next to* the encrypted file — it is mathematically bound *into* it. The
consequence: if someone changes the recorded fingerprint to match a different
photo, **the file stops decrypting altogether.**

Without this, there would be an obvious attack. Swap in a different photo, then
update the stored fingerprint to match it, and verification would happily pass.
Binding the two together means you cannot alter one without destroying the
other.

### Looking at evidence

Tap any item in the vault. The app decrypts it into a temporary file and shows
it — photos with pinch-to-zoom, video and audio with playback — alongside its
details.

The decrypted copy is deleted:

- when the user leaves the screen,
- immediately if panic is triggered or the app is backgrounded,
- and at the next launch, if the app was killed while something was open.

At no point does a readable copy of the evidence sit anywhere on the phone for
longer than the screen is open.

### Verifying evidence — the four fingerprints

This is what the **Verify Integrity** button does, and what the four codes on
that screen mean.

| Shown on screen | What it is | Where it comes from |
|---|---|---|
| **Recorded** | The fingerprint taken at the moment of capture | Read from the encrypted list on the phone |
| **Recalculated** | The fingerprint of what comes out when the file is decrypted right now | Computed fresh, on the spot |
| **Stored file** | The fingerprint of the scrambled file exactly as it sits on the phone today | Computed fresh from the file on disk |
| **Server record** | The fingerprint recorded on the server at capture time | Fetched from the server — the one copy nobody can change |

Then:

- **Recorded matches Recalculated** → the evidence is byte-for-byte what was
  captured.
- **Stored file matches its recorded value** → the scrambled file on disk has
  not been touched or corrupted.
- **Recorded matches the Server record** → the phone's own record has not been
  replaced either. This also compares the capture time, so a record whose date
  has been moved is caught too.

The app always reads the server itself, never a copy it saved earlier. A saved
copy lives on the same phone being checked, so it would prove nothing.

The result is one of three verdicts, and the app never blurs them:

| Verdict | What it means |
|---|---|
| **INTEGRITY VERIFIED** | Every check passed, and the server agrees |
| **VERIFIED ON THIS PHONE** | The phone's checks passed, but the server could not be asked — no internet, or no record there yet. The screen says which |
| **INTEGRITY NOT VERIFIED** | A check failed, or the server disagrees. Never softened |

Being unable to reach the server is not evidence of tampering, and is never
shown as if it were. A server that *disagrees* always is.

### How tampering is actually detected

Every way someone might interfere, and what happens:

| What someone does | What the app does |
|---|---|
| **Edits the encrypted file** — changes even one byte | Decryption fails outright. The "stored file" fingerprint no longer matches. Verification fails |
| **Replaces the file with a different photo** | It will not decrypt: the substitute was not encrypted with this file's key |
| **Changes the recorded fingerprint** in the list | The list is encrypted — editing it breaks it, and the app reports the list as untrustworthy rather than showing an empty vault |
| **Deletes evidence from the phone** | The file is gone, but the record on the server is not. It still proves a file with that fingerprint existed at that time, so the deletion is **provable** |
| **Restores an old copy of the list**, hiding recent captures | The seal does not match. Reported |
| **Corrupts the file accidentally** — storage fault, bad copy | Caught by the same check. The app cannot tell malice from accident, and does not pretend to |
| **Has the phone *and* the PIN, and replaces a file together with its entry in the list** | Everything on the phone now agrees with itself — but not with the server, whose record nobody can change. **INTEGRITY NOT VERIFIED**, naming what disagrees |

Notice what the app does **not** do: guess, or reassure. Anything it cannot
verify is reported as unverified.

### What verification still cannot catch

The server record is only as good as the moment it was made. The app sends it
the next time the vault is opened with an internet connection.

So if a phone is kept **offline from the moment of capture**, there is no server
record to compare against, and verification can only say **VERIFIED ON THIS
PHONE**. Someone who tampered with evidence before it ever reached the server
would not be caught by the server check.

Checking never *creates* a server record, deliberately. If it did, a record
altered on the phone would be sent to the server as though it were the
original, and the check would end up vouching for exactly what it exists to
catch.

### The activity log

The app keeps a record of what happens in it: every time it is opened, every
wrong PIN, every panic, every capture, every time evidence is viewed or
verified, and every PIN change. It is in **Settings → Activity log**.

It records **what** happened and **when** — never filenames, never content.
It is a record of her behaviour, so like everything else it is encrypted, and
it stays on the phone.

What makes it more than a list is that it is **tamper-evident**. Each entry
carries the fingerprint of the entry before it, so the entries form a chain:

- **Change any entry** and its fingerprint no longer matches — and neither does
  the link from the entry after it.
- **Delete an entry** and the chain has a gap, and the numbering jumps.
- **Cut entries off the end**, or put back an older copy of the whole log, and
  the result no longer matches a seal kept in the phone's hardware security
  chip.

The log screen checks all of this every time it opens, and says so at the top:
**Log intact**, or exactly which entry the break is at. Anything from that point
on is marked as not trustworthy.

Wrong PINs and panics happen while the app is locked, when the key to write the
log is not available. They are held securely and added to the log, in the
right order, the next time she unlocks — so they are not lost.

### Panic

**Hold a finger anywhere on the screen for one second.** From any screen, over
any dialog.

Instantly:

1. The key is wiped from the phone's memory — first, before anything is
   redrawn.
2. Every open screen closes.
3. Any message on screen ("Photo saved") is cleared.
4. A fresh calculator appears, showing `0`.

Pressing Back does not return. Getting in again needs the secret sequence and
the PIN.

One second was chosen on purpose: the phone's own long-press is half a second,
so a resting thumb or selecting text will not trigger it, but it is still fast
enough to be useful when someone walks into the room.

### When the app goes to the background

If the user switches apps, presses Home, or the screen turns off, the app locks
itself and forgets the key.

One exception, and it is deliberate: **if a recording is in progress, locking
waits until it finishes.** Recording audio with the screen off is one of the
most realistic ways this app gets used, and the screen turning off counts as
backgrounding — locking there would destroy the key the recording needs to be
saved. Panic ignores this exception, because panic must always be immediate.

### Screenshots

Blocked entirely. Screenshots, screen recording, and casting all fail, and the
app's preview in the recent-apps list is blank rather than showing the vault.

### Changing the PIN

Because of how the layers are arranged, changing the PIN re-locks **one small
key**. No evidence is re-encrypted. It is instant whether there are three items
or three thousand — and all existing evidence still opens with the new PIN.

Wrong attempts here count towards the same lockout, otherwise this screen would
be a way around it.

### Exporting evidence for a lawyer or court

Everything above protects evidence *inside* the app. At some point a lawyer or
a court needs it *outside*. **Export for a lawyer**, in the vault, produces one
file for that: a ZIP holding

- the evidence she chooses, decrypted,
- `manifest.pdf` — for each item: its fingerprints, when it was captured,
  whether it passed verification, and its history from the activity log,
- `manifest.json` — the same, in a form a computer can check,
- `README.txt` — how to open the bundle, and how to check it.

This is the one feature that deliberately takes evidence out of protection, so
it is built around what must not happen:

- **Nothing unverified goes out.** Every item is verified immediately before
  export. One that fails is left out, and the manifest lists it with the
  reason — the gap is visible, not silent.
- **It is password-protected by default.** The bundle is encrypted (AES-256)
  and the app generates a 20-character password, shown once, to be passed on
  **separately** — by phone or on paper, never in the same message as the file.
  That matters here: the email or chat she sends it through may be one an
  abuser can read. Protection can be switched off for a recipient who cannot
  open protected files, and the app says plainly what that means.
- **Nothing decrypted is left on the phone.** The working copies are destroyed
  as soon as the bundle is made, and the bundle itself is destroyed when she
  leaves the export screen — including by panic.
- **Names give nothing away.** Encryption hides what is inside a ZIP but not the
  file names, so every name is neutral: `item-01.jpg`, never the original, and
  the bundle is called `bundle-20260924-140233.zip`, not "evidence".
- **The export is itself recorded** in the activity log, with which items left,
  because handing evidence over is part of its history.

**Anyone can check the bundle without this app.** Each file's fingerprint can
be recalculated with tools already on any computer
(`certutil -hashfile … SHA256` on Windows, `shasum -a 256` on a Mac) and
compared with the manifest. A bundle that could only be checked with our own
app would prove very little.

### What leaves the phone

| Sent | When | Why it is safe |
|---|---|---|
| Fingerprints, date, file size, the locked file key | For every capture | All of it is either a one-way code or something locked with a key that never leaves the phone. Useless to anyone who intercepts or stores it |
| The encrypted evidence file itself | **Never, currently** | See below |
| Name, location, contacts, messages, anything identifying | **Never** | Not collected at all |
| An export bundle | **Only when she creates one** and chooses where to send it | Password-protected by default; neutral names; no keys, no original filenames, and none of her unlock or panic history |

Backing up encrypted copies of the files is built and tested, but **switched
off**: it needs a paid Google plan the project has not taken. The buttons are
still in the app and explain this when tapped.

So today the plain truth is: **evidence media leaves the phone only when she
exports it herself.** What the server provides is proof, not storage.

The app does not contact the internet at all until after the vault is unlocked.
An app that connects to Google the moment it opens would itself be a clue.

---

## Part 3: "What if…"

The questions this project should be able to answer.

**What if he picks up her phone and opens the app?**
He finds a calculator. He can use it. Nothing suggests there is anything else.

**What if he suspects and searches the phone properly?**
He finds an app called Calculator, and a folder of files with meaningless names
that will not open in anything. He cannot tell whether they are evidence,
app data, or nothing.

**What if he tries to guess her PIN while she is away?**
Four guesses are free, then each wrong one makes him wait longer, up to an hour.
He cannot wipe anything by guessing. And the next time she opens the app, she
is told how many wrong PINs were entered and when — even though the lockout
itself has long since reset.

**What if he opens the app, looks around, and closes it again?**
If he knows the PIN, the activity log shows the visit: when it was opened, what
was viewed. He cannot remove those entries without the log saying, at the top,
that it has been tampered with.

**What if he forces her to unlock it?**
Then he sees the evidence. Technology has limits here, and it is important to
say so rather than imply otherwise. The planned defence is a **duress PIN** — a
second PIN that opens a decoy vault with harmless content. It is designed but
not yet built.

**What if he takes the phone and copies everything off it?**
The files are useless without the key, and the key is locked inside the phone's
hardware security chip — it cannot be copied out. He would have to guess the
PIN on the phone itself, where the lockout applies.

**What if the phone is rooted, or he uses forensic tools?**
Then the protection can be broken. We state this openly. Defending against an
attacker with complete control of the operating system requires guarantees the
Android platform does not offer to apps.

**What if he deletes everything?**
The files are gone, but the server records are not — and cannot be deleted.
They prove that evidence with those fingerprints existed at those times, which
makes the destruction itself provable and visible.

**What if he alters a photo to weaken it?**
It will not decrypt. See the table above.

**What if she forgets her PIN?**
The evidence is unrecoverable. We cannot retrieve it; that is the same property
that stops anyone else retrieving it. A printable **recovery code** is planned
to soften this, and until it exists the app warns the user at setup.

**What if the phone is lost, stolen or destroyed?**
The evidence is lost with it, because file backup is currently switched off. The
server records survive and still prove what existed. Turning on backup is one
configuration change away.

**What if an export bundle is intercepted?**
If it was protected — the default — it is encrypted, and the password never
travelled with it. The file names inside reveal nothing. If protection was
turned off, whoever has the file has the evidence; the app warns about exactly
this before it lets her turn protection off.

**What if our own server is hacked, or subpoenaed?**
Whoever obtains it gets fingerprints and locked keys — no photos, no
recordings, nothing identifying a person. The evidence is encrypted before it
would ever leave the phone, with a key we never hold. **We cannot read our
users' evidence, and neither can anyone who takes our database.**

**What if the developers wanted to tamper with a record?**
They cannot. The rule forbidding changes is enforced by the server for every
account, including the one that created the record and including the project's
own administrators.

---

## Part 4: What this app deliberately does not do

A system that claims no weaknesses is not credible. The honest list:

- **It cannot guarantee a court will admit the evidence.** That depends on
  jurisdiction, how it was collected, and the law. The app supports those
  requirements; it does not decide them.
- **It cannot protect against a compromised phone.** A keylogger captures the
  PIN as it is typed.
- **It cannot hide that the app exists** from someone who knows what to look
  for.
- **It cannot help if the user is forced to unlock it** — until the duress PIN
  is built.
- **The activity log can be rebuilt by someone with complete control of the
  phone.** With the PIN *and* root access, it is possible to rewrite the log
  and its seal together. Keeping a copy of each entry's fingerprint on the
  server, like the evidence fingerprints, would close this; it is the natural
  next step. The log's times also come from the phone's clock, which can be
  changed.
- **An exported bundle is only as safe as where it goes.** Once shared, the
  receiving person's copy is outside the app entirely. Password protection
  keeps it unreadable in transit, not after the recipient opens it.

---

## Part 5: Glossary

| Term | Meaning |
|---|---|
| **Encryption** | Scrambling data so it is unreadable without the key |
| **AES-256** | The encryption standard used, the same one used by banks and governments |
| **SHA-256 fingerprint (hash)** | A 64-character code calculated from a file. Same file, same code, always. Any change produces a completely different code. Cannot be reversed |
| **Key** | The secret that unscrambles encrypted data |
| **Master key** | The single key protecting all the others; locked by the PIN |
| **Keystore** | A hardware security chip in the phone. Keys inside it cannot be copied out |
| **Firestore** | The Google database holding the unchangeable records |
| **Security rules** | Instructions on the server saying who may do what. Ours forbid changing or deleting a record |
| **Anonymous sign-in** | Each phone gets an ID with no email or phone number attached |
| **Metadata** | Information *about* a file — its size, date, fingerprint — rather than its contents |
| **Hash chain** | A list where each entry includes the fingerprint of the one before it, so changing or removing any entry breaks every link after it |

---

## Part 6: Seeing it for yourself

A ten-minute demonstration, in the order that shows the most:

1. **Open the app.** A calculator. Use it.
2. **Type the wrong sequence.** Just arithmetic. Nothing happens.
3. **Type the real sequence**, enter the PIN, and the vault opens.
4. **Enter a wrong PIN five times** — a countdown appears. Close the app
   entirely, reopen it: still locked out.
5. **Take a photo in the app.** Then open the phone's own gallery — *it is not
   there.*
6. **Copy the encrypted file off the phone and try to open it.** It will not
   open in any viewer.
7. **Open the item in the app.** It displays normally.
8. **Tap Verify Integrity.** Watch all four fingerprints match — including the
   one fetched from the server.
9. **Hold the screen for one second.** Instant calculator. Press Back — it does
   not return. Getting in needs the PIN again.
10. **Enter a wrong PIN twice, then the right one.** A notice says two wrong
    PINs were entered, and when. Open **Settings → Activity log**: the wrong
    PINs, the panic and the unlock are all there, under **Log intact**.
11. **Export two items for a lawyer.** Note the password, share the bundle to
    a laptop, open it with 7-Zip, and run `shasum -a 256` on each file — the
    values match `manifest.pdf` exactly.
12. **In the Firebase console**, find the record. It contains only fingerprints
    and a date. **Then try to delete it — the server refuses. Try to edit it —
    refused.** Even as the owner of the project.

Step 12 is the one to end on. Every other feature is something a reviewer could
reasonably take on trust. That one can be watched, live, refusing.
