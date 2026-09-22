# Phase 9: transactional merge

`MergeTransaction` is the pure domain state machine. It owns stable conflict
identities, choices, active-conflict navigation, stale state, and the apply
report. It does not call Neovim APIs. `MergeProjection` owns buffers and
extmarks; `MergeSession` is the adapter that reads Git stages, projects edits,
and performs filesystem effects.

## Apply boundary

Apply has four visible phases: prepare, validate, write, and report. Validation
rejects changed index stages, changed worktree bytes, and symlink targets. Every
result is written to a temporary sibling before any destination is changed.
Each individual destination replacement is atomic. A multi-file replacement is
not filesystem-atomic: completed paths are rolled back in reverse order after a
later failure, and every rollback failure is retained in `report.rollback_failures`.

Regular-file permission bits are preserved. Symlinks are deliberately rejected
instead of followed. ACLs, xattrs, ownership, and platform-specific metadata are
best effort because libuv has no portable copy-metadata API; the report states
this policy rather than claiming preservation. The original file is renamed to
a backup during the commit window, so its full metadata remains available for
rollback.

## UI behavior

Conflict rows expose OURS, BASE, THEIRS, ALL, and MANUAL buttons. The Result
action bar exposes those choices, whole-file choices, identity-based previous
and next navigation, and Apply. A failed stale validation shows a banner with
Refresh, Reopen, and Discard. Reopen reconstructs the transaction from the
current index and worktree; Discard force-closes without writing Result buffers.
