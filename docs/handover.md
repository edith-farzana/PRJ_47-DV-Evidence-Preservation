# Handover

## Current state
_Last updated: 2026-10-24 · claude-opus-5-5_
- Working on: P8 (offline sync). The metadata half is done on branch
  `claude/busy-kalam-aac46d`, not pushed and not merged.
- Done: the server record is now sent straight after capture and at every
  unlock, not only when the vault opens. See
  `docs/features/2026-10-24-metadata-at-capture-and-unlock.md`. 220 Dart tests
  pass and `flutter analyze` is clean (Flutter 3.47.8).
- Next step: an on-device check (steps in the feature file). Then the rest of
  P8: a blob upload queue with backoff, and per-item sync status.
- Blocked on / open questions: none.
- Gotchas:
  - Flutter isn't installed system-wide. This session used a copy in a
    temporary scratchpad.
  - Any `flutter` command runs `pub get`, which with Flutter 3.47.8 rewrites
    the linux/macos/windows plugin registrants. The committed ones are stale
    (no `share_plus` or `video_player`). Don't commit those files alongside
    unrelated work.
  - Never `await` `EvidenceSync.recordCaptured` or `catchUp` from a screen or
    the lock path. Offline, the Firestore SDK may hold a `set()` open until it
    gets a signal (expected SDK behaviour, not checked on a device here).
  - `backUp()` writes metadata without logging `recordedOnServer`. It can't be
    reached while Storage is off.

## Session log
_Newest first. One short entry per session._

### 2026-10-24 · claude-opus-5-5
- What changed: metadata sync at capture (`saveCapture`) and at unlock
  (`AppLockController.afterUnlock` → `EvidenceSync.catchUp`). The activity-log
  entry moved into `EvidenceSync.onRecorded`. 13 new tests. `HOW_IT_WORKS.md`
  and the checklist are updated.
- Why: a review found the immutable record was written only when the vault
  opened, which weakened the project's main claim.
- Left unfinished: the on-device check; the rest of P8.
