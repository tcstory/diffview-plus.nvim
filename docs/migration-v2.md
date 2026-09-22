# Migration to the minimal UI architecture

The refactor deliberately removes configuration aliases that made it unclear
which interaction model was active. Neovim 0.12 is now the API baseline.

## Keymaps and actions

Choose one built-in preset and add mappings by stable action ID:

```lua
require("diffview").setup({
  keymaps = {
    preset = "minimal", -- or "none"
    interaction = "hybrid", -- "mouse", "hybrid", or "keyboard"
    file_panel = {
      { "n", "s", "diff.toggle_stage_entry" },
    },
  },
})
```

`key_bindings` and `keymaps.disable_defaults` were removed. Replace callback
lookups such as `require("diffview.config").diffview_callback(name)` with
`require("diffview.api").actions.callback("<action-id>")`. The removed entry
points raise an error that includes this replacement.

## Panel and layout options

- Move panel-local `use_icons` to the top-level `use_icons` option.
- Put panel `position`, `width`, and `height` inside `win_config`.
- Use `file_history_panel.log_options.<adapter>`; the former direct history
  log options are rejected.
- Replace the internal `diff1_*_pinned` and `diff2_*_pinned` layout names with
  their standard `diff1_*` or `diff2_*` names. `--pin-local` now stores
  borrowed-file ownership on the FileHistory view state.

## Internal integrations

`_G.DiffviewGlobal`, `diffview.job`, `diffview.multi_job`, and
`diffview.job_utils` were never public APIs and have been removed. Internal
integrations should use `diffview.runtime.context`, `ProcessTask`, and
`ProcessGroup`. Subprocesses are backed by `vim.system()` and accept an
environment map rather than a list of `KEY=VALUE` strings.

Run `:checkhealth diffview` after migrating. It reports the Neovim baseline,
UI preset, interaction mode, active adapter, and adapter capabilities.
