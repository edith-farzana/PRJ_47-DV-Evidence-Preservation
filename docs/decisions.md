# Decisions

_Newest first. Log the why, not just the what._

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
