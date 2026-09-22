# Phase 8: FileHistory

Phase 8 moves file history onto an explicit streaming state model and exposes
the everyday workflow through clickable controls.

## Query state

`scene/views/file_history/store.lua` owns entries, the pin-local ViewState, and
the active query generation. A query transitions through `streaming`,
`success`, `error`, or `cancelled`, reports received commit count through a
Neovim progress message, and owns a cooperative cancellation token. Refresh,
view close, and the visible Cancel action all cancel the active stream; stale
generations cannot append after a replacement query starts.

## Mouse workflow and context actions

The history panel winbar exposes Actions, Filters, Cancel, Details, Copy hash,
Diff HEAD, and Restore. Filters opens the existing adapter-specific option
model as a clickable UI, so switches and values no longer require memorized
keys. The legacy option-panel action remains available during the compatibility
window, but the discoverable toolbar is the primary entry point.

## Pin-local ViewState

Pin-local mode and its shared working-tree files now live in
`FileHistoryStore.view`. Standard Diff1 and Diff2 layout classes receive
borrowed b-side ownership and pin-local null semantics on their instances.
Production selection and layout cycling therefore no longer substitute four
specialized pinned layout subclasses. Those compatibility modules were removed
in Phase 10; old `_pinned` layout names now raise a migration error.

## Incremental history components

The panel creates the header and history component roots once per query reset.
As commits stream in, only new entry components are appended; existing
component identity is preserved. The renderer's line patching then writes the
changed suffix instead of rebuilding and replacing the full history tree.

The Phase 8 contract tests cover query transitions, cancellation and stale
generation rejection, a 512-entry incremental append, toolbar actions, and
pin-local ownership across standard-layout conversion.
