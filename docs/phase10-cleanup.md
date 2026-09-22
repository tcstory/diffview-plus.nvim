# Phase 10: cleanup and documentation

The release surface now has only `minimal` and `none` keymap presets. Removed
configuration aliases fail immediately with a replacement, and the migration
guide records every removed user-facing entry point.

Cleanup removed the global runtime table, the legacy Job/MultiJob stack, and
the four pin-local layout subclasses. Process execution now uses `vim.system()`
through small `ProcessTask` and `ProcessGroup` contracts. FileHistory carries
pin-local ownership on ordinary layout instances.

`:checkhealth diffview` reports the 0.12 API baseline, UI preset, interaction
mode, deprecated-config policy, detected adapters, active adapter, and sorted
capabilities. The architecture guide links the action path and all three view
data flows; README, help, recipes, and the migration guide use action IDs and
the discoverable palette/toolbars.

The final audit removed `oop.lua`, `renderer.lua`, and `ui/model.lua`. Scene
objects, layouts, panels, adapter facades, streams, renderer data, and value
types now use ordinary annotated Lua tables. Rendering is consolidated in
`ui/component_renderer.lua`; there is no parallel legacy renderer.

The 1,765-line configuration module is now split into defaults/schema, log
options, validation, migration policy, and a runtime facade. The source-based
schema gate reads the defaults module directly, so explicitly nil options are
still checked. Scale contracts for 1,000-entry DiffView/FileHistory workloads,
a 1,000-line renderer patch, and 100 merge conflicts are recorded in
`docs/performance-baselines.md`.

`runtime/effect_scope.lua` gives every `ViewShell` one cancellation boundary.
Index watchers, file-history debounce handles, subscriptions, scheduled
callbacks, and `vim.system()` tasks register explicit disposers there.

One intentional boundary remains: Neovim 0.12 has no stable `vim.async`, while
the view and adapter call graph still needs sequential coroutine coordination.
`async.lua` therefore remains active runtime code, not compatibility code. It
does not spawn processes or own view resources. Renaming it would only hide the
constraint; replacing it requires either callback-style rewrites of every
caller or a future stable Neovim primitive. The deletion ledger records this
version-gated decision explicitly.

The final documentation pass also replaced the pre-refactor developer guide,
updated the architecture walkthrough and deletion ledger, and synchronized the
plan checklist with verified tests and commits.
