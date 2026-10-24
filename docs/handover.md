# Handover

## Current state
_Rewrite this section each time. Last updated: 2026-10-24 · claude-opus-5-5_
- Working on: waiting for the owner's on-device feedback on the release APK.
- Done:
  - The dev toolchain is installed globally on this Mac (see "Dev environment"
    below), and the Firebase config files are generated locally (gitignored).
  - P8 metadata half merged to `main` (PR #9, `a0c4f5a`): the server record is
    sent straight after capture and at every unlock. See
    `docs/features/2026-10-24-metadata-at-capture-and-unlock.md`.
  - On `a0c4f5a`: `flutter analyze` clean, 220/220 Flutter tests pass, 15/15
    rules tests pass on the emulator.
  - Release APK built from `a0c4f5a` and copied to
    `~/Desktop/SecureEvidence-v1.0.0-build1-a0c4f5a-release.apk` (60.7 MB,
    sha256 `53827b64…0e123f67`). Installed and launched on the
    `Pixel_8_API_36` emulator: it reaches the first-run Set up screen with no
    crashes. Not taken past setup there, so no Firebase traffic was tested.
  - Only `main` remains, locally and on GitHub. The deleted branches
    (`master`, `feature/court-export`, `claude/busy-kalam-aac46d`) were all
    fully contained in `main`.
- Next step: the on-device check of the P8 change (steps in the feature file)
  using the Desktop APK, then the rest of P8: a blob upload queue with backoff,
  and per-item sync status.
- Blocked on / open questions: the owner's device feedback.
- Gotchas:
  - Screenshots and `adb screencap` of the app are black by design:
    `MainActivity.kt` sets `FLAG_SECURE`. Read the screen with
    `adb shell uiautomator dump` instead.
  - Launch it on a device with
    `adb shell am start -n com.pocketcalc.calculator/.MainActivity`;
    `adb shell monkey -p …` failed (exit -5) on the emulator.
  - Release builds are signed with the debug key (`android/app/build.gradle.kts`).
    Fine for sideloading, not for the Play Store.
  - The JDK is Homebrew's keg-only `openjdk@21`, not a system JDK. `/usr/bin/java` still says "Unable to locate a Java Runtime"; use the `JAVA_HOME` set in `~/.zshrc`. Flutter is pointed at it with `flutter config --jdk-dir`.
  - The Android SDK lives at `/opt/homebrew/share/android-commandlinetools`, not `~/Library/Android/sdk`.
  - The `PERMISSION_DENIED` lines in the rules-test output are the denials the tests expect, not failures.
  - Never `await` `EvidenceSync.recordCaptured` or `catchUp` from a screen or
    the lock path. Offline, the Firestore SDK may hold a `set()` open until it
    gets a signal (expected SDK behaviour, not checked on a device here).
  - `backUp()` writes metadata without logging `recordedOnServer`. It can't be
    reached while Storage is off.

## Dev environment
Installed 2026-10-24. PATH and env vars are in the "Flutter / Android / Firebase toolchain" block at the end of `~/.zshrc` (the earlier version is backed up at `~/.zshrc.bak-before-flutter-setup`).

| Tool | Version | Installed with |
|---|---|---|
| Flutter / Dart | 3.47.7 / 3.13.5 | `brew install --cask flutter` |
| OpenJDK | 21.0.12.1 | `brew install openjdk@21` |
| Android cmdline-tools | latest (cask 15859902) | `brew install --cask android-commandlinetools` |
| Android SDK packages | platform-tools 37.0.1, platforms;android-36, build-tools 36.1.0 (Gradle also pulled in android-35, android-34 and build-tools 36.0.0 for plugins on the first build), ndk 28.2.13676358, emulator 37.2.12, system image android-36 google_apis arm64-v8a | `sdkmanager` |
| Android emulator device | `Pixel_8_API_36` | `avdmanager` |
| Firebase CLI | 15.34.1 | `npm install -g firebase-tools` |
| FlutterFire CLI | 1.4.1 | `dart pub global activate flutterfire_cli` |

Not installed: Xcode and CocoaPods (only needed for iOS/macOS builds; this app is Android only).

Run the checks:
- `flutter test`
- `firebase emulators:exec --only auth,firestore,storage "npm --prefix test/rules test"` (run `npm --prefix test/rules ci` once first)

Undo: `brew uninstall --cask flutter android-commandlinetools`, `brew uninstall openjdk@21`, `npm uninstall -g firebase-tools`, `dart pub global deactivate flutterfire_cli`, then restore `~/.zshrc` from the backup.

## Session log
_Newest first. One short entry per session._

### 2026-10-24 · claude-opus-5-5 (README split and ABOUT.md)
- What changed: the README is now the setup guide, the launch video
  (`docs/media/launch-video.mp4`, poster beside it) and a short description.
  Everything else moved to a new `ABOUT.md`: the origin story with cited Indian
  figures, the problem, the solution, what works today, the technical design
  and the legal notes. Also dropped a stray `</p>` left at the end of the
  README by `91d21f9`.
- Why: owner asked for the two-part split and the video in the README.
- Left unfinished: optional inline player. Drag the MP4 into any GitHub comment
  box, then swap the poster link in the README for the URL GitHub gives.

### 2026-10-24 · claude-opus-5-5 (/brag launch video)
- What changed: made a launch video in `brag-output/` (`brag.mp4`,
  poster `brag.jpg`, `share-copy.txt`, plan, brief, and the Hyperframes
  0.8.191 project in `brag-output/composition/`). The app's screens are
  recreated in HTML from the Flutter source, with made-up filenames,
  dates and hashes. No app code changed. Later the same day it grew from
  25 s to 32.75 s to show the full integrity check (Evidence Detail →
  four fingerprints → INTEGRITY VERIFIED) and a swapped file being caught
  (INTEGRITY NOT VERIFIED). The 25 s composition is kept at
  `brag-output/work/index.before-integrity.html`.
- Why: owner ran `/brag`, then asked for the integrity check to be shown.
- Left unfinished: nothing. `brag-output/` is gitignored on purpose (local
  media, a ~2.6 MB music file and `.hyperframes/` artifacts). Re-render with
  `npx hyperframes render --quality delivery --output ../brag.mp4` from
  `brag-output/composition/`, then redo the poster/audio pass described in
  `brag-output/brag-plan.md` ("As built").

### 2026-10-24 · claude-opus-5-5 (tests, branch cleanup, release APK)
- What changed: re-ran every test suite on `a0c4f5a` with the real Firebase
  config; deleted every branch except `main` locally and on GitHub (and the
  merged session's worktree); built the release APK to the Desktop and
  smoke-launched it on the emulator.
- Why: owner asked for a full test pass, a single-branch repo, and an APK to
  try on a phone.
- Left unfinished: on-device testing of the features (owner).

### 2026-10-24 · claude-opus-5-5 (P8 metadata sync)
- What changed: metadata sync at capture (`saveCapture`) and at unlock
  (`AppLockController.afterUnlock` → `EvidenceSync.catchUp`). The activity-log
  entry moved into `EvidenceSync.onRecorded`. 13 new tests. `HOW_IT_WORKS.md`
  and the checklist are updated. Verified with Flutter 3.47.8 in a scratch
  copy, before the global toolchain landed on `main`.
- Why: a review found the immutable record was written only when the vault
  opened, which weakened the project's main claim.
- Left unfinished: the on-device check; the rest of P8.

### 2026-10-24 · claude-opus-5-5 (toolchain)
- What changed: installed the Flutter, Android, Java and Firebase toolchain globally; fetched pub and npm packages; created this file and `decisions.md`.
- Why: the machine had none of the tools needed to build or test the app.
- Left unfinished: Firebase config files (needs the owner's sign-in); the regenerated plugin registrant files are uncommitted.
