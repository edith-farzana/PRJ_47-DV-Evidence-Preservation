# Feature: Server record at capture and at unlock

_Started 2026-10-24 · claude-opus-5-5 · Status: done (device check pending)_

## Goal
Every capture gets its immutable Firestore record without the survivor having
to open the vault. Before this, the record was written only when the vault
screen opened (`evidence_vault_page.dart`), so someone who captured and never
reopened the vault while online left no server record. That broke the
project's main claim, that a capture's existence can be proven.

## Approach
One send path, `EvidenceSync.syncPendingMetadata`, now called from three
moments:

1. **Capture.** Both capture screens go through `saveCapture()`, which waits
   only for `EvidenceStorage.addEvidence`, then starts
   `EvidenceSync.recordCaptured` without awaiting it. It never throws.
2. **Unlock.** `AppLockController` takes an `afterUnlock` hook, started but not
   awaited from `unlocked()`. `main.dart` points it at
   `EvidenceSync.catchUp(storage.getEvidence, keepGoing: keyManager.isUnlocked)`.
3. **Vault open**: unchanged, kept as a further catch-up.

Supporting changes:
- `onRecorded` callback on `EvidenceSync`. `main.dart` writes the
  `recordedOnServer` activity-log entry from it, so every path logs exactly
  once. The vault's own logging loop was removed.
- An in-flight set, so overlapping triggers never send the same record twice.
- `keepGoing` is checked before each write, so a panic stops new writes. A
  write already on its way is left to finish.
- The payload is still `metadataPayload()` only.

Alternatives are in `decisions.md`.

## Changes
| File | What changed |
|---|---|
| `lib/services/sync/evidence_sync.dart` | `onRecorded`, in-flight de-dupe, `keepGoing`, re-read state after the write; new `recordCaptured` and `catchUp` |
| `lib/features/evidence/capture/save_capture.dart` | New. The shared capture sequence: store, log "captured", start the server record |
| `lib/features/evidence/capture/audio_capture_page.dart` | Uses `saveCapture` |
| `lib/features/evidence/capture/in_app_camera_page.dart` | Uses `saveCapture` |
| `lib/app/app_lock_controller.dart` | Optional `afterUnlock` hook, fire-and-forget, errors contained |
| `lib/main.dart` | Builds `sync` before the lock controller; wires `onRecorded` and `afterUnlock` |
| `lib/features/vault/evidence_vault_page.dart` | Dropped its own `recordedOnServer` loop (now in `onRecorded`) |
| `test/services/evidence_sync_test.dart` | 9 tests through the real capture path and the unlock wiring |
| `test/app/app_lock_controller_test.dart` | 4 tests: hook not awaited, not run before the PIN, errors contained, panic still instant |
| `docs/HOW_IT_WORKS.md`, `DEVELOPMENT_CHECKLIST.md` | Describe the new timing; P8 marked started |

## Test checklist
- [x] `flutter analyze`: no issues (Flutter 3.47.8 / Dart 3.13.7)
- [x] `flutter test`: 220/220 pass (207 before, 13 new)
- [x] Mutation check, one change at a time in a scratch copy. Each was caught:
      no send at capture (8 tests fail), unlock hook never called (4),
      capture awaiting the server (2), no in-flight de-dupe (1), no `keepGoing`
      guard (1)
- [ ] Firestore rules tests (15): not run. The rules are unchanged.
- [ ] On device: airplane mode on, capture, close the app. Airplane mode off,
      unlock, don't open the vault. The record appears in the Firebase console
      and the Activity log shows "recorded on server".

## Rollback
Revert the commit. No data migration is involved: `BackupStateStore` keeps
the same `metadataSynced` field, and the Firestore rules are untouched.

## Follow-ups
- `backUp()` writes metadata without calling `onRecorded`, so that path logs
  no `recordedOnServer` entry. It can't be reached while Storage is off.
- The catch-up is sequential. Offline with a signed-in user, the first
  pending write holds the loop until the signal returns. The P8 queue with
  backoff should replace this.
