# Architecture walkthrough

This guide starts at the smallest stable modules and follows one user action
through each view. Phase-specific details remain in `docs/phase3-actions.md`
through `docs/phase9-merge.md`.

## From an entry point to an action

1. `plugin/diffview.lua` defines commands and starts `diffview.bootstrap`.
2. `diffview.init` parses command arguments and asks `diffview.lib` to create a
   view with the adapter selected by `diffview.vcs`.
3. A key, toolbar button, row click, or palette item resolves to a stable ID in
   `runtime/action_registry.lua`.
4. `ui/router.lua` resolves the component and invokes that action with an
   explicit context. The action checks adapter capabilities before dispatch.
5. A view command changes domain/store state. Components project the new state
   and the renderer updates the Neovim buffer. Owned timers, subscriptions,
   processes, buffers, and windows are closed with their view lifecycle.

The important direction is one-way: input → action → domain/store → projection.
Adapters return data and capability results; they do not render UI.

## DiffView data flow

`DiffviewOpen` → adapter status query → `DiffStore` → file-panel components →
selected `FileEntry` → standard layout and buffer leases. Stage, restore,
review, filter, and refresh controls dispatch `DiffCommand` values back to the
store. Refresh generations prevent a superseded query from publishing stale
results.

## FileHistory data flow

`DiffviewFileHistory` → adapter history query → cancellable streaming batches →
`FileHistoryStore` → append-only entry components. Filter controls rebuild the
query model. In pin-local mode, the store owns working-tree files and standard
layout instances mark the local side as borrowed; no special layout subclass
is involved.

## MergeView data flow

`DiffviewMergeOpen` → adapter conflict snapshot → `MergeTransaction` →
`MergeProjection` buffers/extmarks → clickable conflict rows and action bar.
Apply executes prepare → validate → write → report. A stale index or worktree
becomes visible state with Refresh, Reopen, and Discard actions. Per-file
replacement is atomic; multi-file rollback is best effort and fully reported.

## Suggested reading order

1. `runtime/action_registry.lua` and `vcs/capability.lua`
2. `scene/views/diff/store.lua` and `scene/views/diff/command.lua`
3. `scene/views/file_history/store.lua` and `vcs/query.lua`
4. `merge/transaction.lua`, `merge/projection.lua`, and `merge/session.lua`
5. `ui/component.lua`, `ui/router.lua`, and `ui/component_renderer.lua`
6. `runtime/effect_scope.lua`, `runtime/process_task.lua`,
   `runtime/process_group.lua`, and adapter ports

Scene objects, layouts, panels, adapters, renderer data, and value types are
plain annotated Lua tables. The former class framework and renderer facade
have been deleted; `ui/component_renderer.lua` is the single buffer/extmark
projection implementation.

Coroutine coordination remains an internal runtime primitive on Neovim 0.12,
which does not provide stable `vim.async`. It no longer owns subprocesses:
`vim.system()` and `EffectScope` own process execution and cancellation. This
boundary is documented in `docs/phase10-cleanup.md` and must be reconsidered
when the minimum supported Neovim version exposes a stable replacement.
