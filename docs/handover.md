# Handover

## Current state
_Rewrite this section each time. Last updated: 2026-10-24 · claude-opus-5-5_
- Working on: P8 (offline sync). The metadata half is done on branch
  `claude/busy-kalam-aac46d`, in a PR against `main`.
- Done:
  - The dev toolchain is installed globally on this Mac (see "Dev environment"
    below).
  - The server record is now sent straight after capture and at every unlock,
    not only when the vault opens. See
    `docs/features/2026-10-24-metadata-at-capture-and-unlock.md`. 220 Dart
    tests pass and `flutter analyze` is clean.
  - The Firestore/Storage rules tests pass on the emulator (15 tests). The
    rules are unchanged by the P8 work.
- Next step: generate the Firebase config files (`firebase login`, then
  `flutterfire configure`, Android only) so `flutter build apk` and
  `flutter run` work. Then the on-device check of the P8 change (steps in the
  feature file), then the rest of P8: a blob upload queue with backoff, and
  per-item sync status.
- Blocked on / open questions: `android/app/google-services.json` and
  `lib/firebase_options.dart` are not in git by design, and creating them needs
  the owner's Firebase sign-in.
- Gotchas:
  - The JDK is Homebrew's keg-only `openjdk@21`, not a system JDK. `/usr/bin/java` still says "Unable to locate a Java Runtime"; use the `JAVA_HOME` set in `~/.zshrc`. Flutter is pointed at it with `flutter config --jdk-dir`.
  - The Android SDK lives at `/opt/homebrew/share/android-commandlinetools`, not `~/Library/Android/sdk`.
  - `flutter pub get` on Flutter 3.47.7 rewrites the generated plugin registrants for linux/macos/windows to match the current pubspec (adds share_plus and video_player, drops file_selector). The diff is expected.
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
