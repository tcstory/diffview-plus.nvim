# Phase 3 developer note: actions and minimal keymaps

Phase 3 makes `runtime/action_registry.lua` the single declaration source for
interactive behaviour. An action owns a stable ID, label, description,
category, availability predicate, implementation, and optional danger/confirm
metadata.

## Data flow

```text
keymap / palette / toolbar
          │ action ID
          ▼
ActionRegistry ── availability + reason
          │
          ├── dangerous ── Confirm service
          ▼
domain action implementation ── view event / state change
```

Keymaps store IDs and are resolved to stable callbacks at the Neovim boundary.
This means help text and disabled reasons come from the same declaration used
to execute the action. `ui/action_palette.lua` and `ui/toolbar.lua` consume the
same registry metadata.

## User configuration

```lua
require("diffview").setup({
  keymaps = {
    preset = "minimal", -- or "none"
    file_panel = {
      { "n", "s", "diff.toggle_stage_entry" },
      { "n", "R", "file.refresh_files" },
    },
  },
})
```

Use `require("diffview.api").actions.list()` to discover IDs. The compatibility
functions under `require("diffview.actions")` remain callable, but new code
should use IDs so availability and confirmation cannot be bypassed.

## Ownership

- `actions/{navigation,file,history,diff,merge,layout,view}.lua` owns action
  declarations for its domain.
- `runtime/action_registry.lua` owns lookup, availability and execution.
- `runtime/confirm.lua` owns dangerous-action confirmation.
- `runtime/keymaps.lua` owns action-ID-to-callback resolution.
- UI consumers own presentation only; they do not duplicate action labels or
  capability rules.
