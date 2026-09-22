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

The final audit also corrected the deletion boundary: `oop.lua`, `async.lua`,
and the scene renderer still have live production callers. They are not
compatibility modules and are therefore retained until their callers can be
migrated as independent vertical slices. Keeping an active core is preferable
to relabeling it as dead code and breaking view dispatch.
