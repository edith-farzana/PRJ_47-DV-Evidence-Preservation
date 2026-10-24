# Decisions

_Newest first. Log the why, not just the what._

### 2026-10-24 · README split, and the launch video committed to the repo
- Context: the owner asked for the README to hold only the setup guide, the
  launch video and a short description, with everything else, including how
  the idea came about, in a second document.
- Options for the video:
  A. Upload it through GitHub's web editor for an inline player (a manual
     step, and the file lives outside the repo).
  B. Commit the MP4 and a poster to `docs/media/`; the poster links to it.
  C. B now, then switch to A's inline player once the owner uploads it.
- Decision: C. Part 2 lives in `ABOUT.md` at the repo root (owner's choice).
- Why: B works as soon as it merges, with no manual step; a 4.1 MB binary in
  history is an acceptable cost. The origin story uses only figures with a
  source: "about 40% of cases pending" was dropped (no source found) for the
  4.71 lakh pending Domestic Violence Act cases the Supreme Court cited in
  February 2023, and "85–90% never reach an FIR" is stated as NFHS-5's 86% who
  sought no help at all. Model: claude-opus-5-5.

### 2026-10-24 · When the server record is sent
- Context: metadata reached Firestore only when the vault screen opened. A
  capture made by someone who never reopened the vault while online got no
  immutable record.
- Options:
  A. Send at capture, and catch up at every unlock (the vault stays a third
     chance).
  B. Watch connectivity (`connectivity_plus`) and send whenever the signal
     returns.
  C. Background job (WorkManager).
- Decision: A.
- Why: B and C can fire while the app is locked and showing the calculator.
  "No network before unlock" is a safety rule here: an app that contacts
  Google while it looks like a calculator gives itself away. B and C also add
  dependencies. Capture and unlock are the moments the app is legitimately
  open. Revisit if device tests show records are often still missing because
  people rarely unlock with signal.
- Made by: claude-opus-5-5, from the task the review session set

### 2026-10-24 · A lock stops new writes, but not one already sent
- Context: the unlock catch-up can still be running when she panics.
- Options: A. Stop starting writes once locked. B. Carry on regardless.
  C. Try to cancel the write in flight.
- Decision: A.
- Why: after a panic the app should go quiet, so no new traffic starts. The
  write in flight can't be cancelled cleanly. It carries metadata only, and
  is the record most worth having if the phone is about to be taken. Panic
  itself never waits on any of it.
- Made by: claude-opus-5-5

### 2026-10-24 · The activity-log entry comes from the sync service
- Context: three paths now send records. Each must log `recordedOnServer`
  exactly once, because the export manifest builds each item's history from
  the log.
- Options: A. Each caller logs. B. An `onRecorded` callback on `EvidenceSync`,
  wired to the audit log in `main.dart`.
- Decision: B.
- Why: one place, so a new path can't forget the entry or log it twice.
  `EvidenceSync` stays free of `AuditLog` and Firebase, so it stays testable
  with fakes.
- Made by: claude-opus-5-5

### 2026-10-24 · The unlock hook lives on AppLockController
- Context: something has to start the catch-up at unlock.
- Options: A. Wrap `PinPage.onSuccess` in `app.dart`. B. An optional
  `afterUnlock` hook on `AppLockController.unlocked()`.
- Decision: B.
- Why: `unlocked()` is the single way into the unlocked state, and it already
  starts the audit fold the same fire-and-forget way. It can be tested without
  pumping widgets.
- Made by: claude-opus-5-5

### 2026-10-24 · JDK 21 from Homebrew's keg-only formula
- Context: the Android build needs JDK 17+ (AGP 9.1, Gradle 9.3.1, Java 17 target), and the Firebase emulators used by the rules tests need JDK 21+.
- Options: A) Temurin cask (installs into `/Library/Java`, needs an admin password); B) Homebrew `openjdk@21` formula (keg-only, no password); C) Android Studio's bundled JBR (pulls in the whole IDE).
- Decision: B, JDK 21, wired in via `JAVA_HOME` in `~/.zshrc` and `flutter config --jdk-dir`.
- Why: one JDK covers both Gradle and the emulators, and installing it needs no sudo. Revisit if a tool insists on `/usr/libexec/java_home` finding a system JDK. The fix then is `sudo ln -sfn /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk-21.jdk`.
- Made by: claude-opus-5-5

### 2026-10-24 · Android SDK from command-line tools, not Android Studio
- Context: the app needs an Android SDK to build and an emulator to run without a phone.
- Options: A) Android Studio (GUI, several GB, manages its own SDK); B) `android-commandlinetools` cask plus `sdkmanager`.
- Decision: B, with the SDK at `/opt/homebrew/share/android-commandlinetools` and only the packages Flutter 3.47.7 asks for (android-36, build-tools 36.1.0, NDK 28.2.13676358) plus an emulator image.
- Why: smaller, scriptable, and enough for `flutter build` and `flutter run`. Android Studio can still be added later and pointed at this SDK.
- Made by: claude-opus-5-5
