# Compatibility Inventory

> Phase 0 baseline — 2026-09-19  
> This document lists every user-facing surface that an external consumer may
> depend on.  It is the reference for deciding what needs a migration note
> when changed or removed.

---

## 1. User Commands

Registered in `plugin/diffview.lua` via `nvim_create_user_command`.

| Command | Args | Bang | Range | Notes |
|---------|------|------|-------|-------|
| `:DiffviewOpen [rev]` | `*` | — | — | Open diff view; routes to MergeView on conflicts |
| `:DiffviewMergeOpen [rev]` | `*` | — | — | Force-open MergeView |
| `:DiffviewToggle [rev]` | `*` | — | — | Toggle diff view |
| `:DiffviewDiffFiles <f1> <f2>` | `+` | — | — | Diff two arbitrary files (no VCS required) |
| `:DiffviewMergeFiles <ours> <base> <theirs> <result>` | `+` | — | — | Open merge tool for four explicit files |
| `:DiffviewDiffDirs <dir1> <dir2>` | `+` | — | — | Directory diff |
| `:DiffviewFileHistory [paths…]` | `*` | — | ✓ | File/line history; accepts visual range |
| `:DiffviewClose` | 0 | ✓ | — | Close current Diffview; `!` forces |
| `:DiffviewFocusFiles` | 0 | — | — | Focus the file panel |
| `:DiffviewToggleFiles` | 0 | — | — | Toggle file panel visibility |
| `:DiffviewRefresh` | 0 | ✓ | — | Refresh file list; `!` forces |
| `:DiffviewLog` | 0 | — | — | Open debug log file |

All commands share a single tab-completion function (`diffview.completion`).

---

## 2. Public Lua API

Exposed through `require("diffview")`.

| Function | Signature (approximate) | Notes |
|----------|-------------------------|-------|
| `setup(opts?)` | `opts: DiffviewConfig.user` | Must be called before opening views; idempotent |
| `open(args?)` | `args: string[]` | Programmatic `:DiffviewOpen` |
| `merge_open(args?)` | `args: string[]` | Programmatic `:DiffviewMergeOpen` |
| `toggle(args?)` | `args: string[]` | Programmatic `:DiffviewToggle` |
| `diff_files(args)` | `args: string[]` | Programmatic `:DiffviewDiffFiles` |
| `merge_files(args)` | `args: string[]` | Programmatic `:DiffviewMergeFiles` |
| `dir_diff(args)` | `args: string[]` | Programmatic `:DiffviewDiffDirs` |
| `file_history(range?, args?)` | `range: [integer,integer]?; args: string[]` | Programmatic `:DiffviewFileHistory` |
| `close(view?, opts?)` | `view: View?; opts: {force?:boolean}` | Close a specific or current view |
| `emit(event, …)` | string event name + varargs | Internal event dispatch; not a stable public API |
| `nore_emit(event, …)` | same | Non-re-entrant emit; not a stable public API |
| `completion(…)` | command-completion callback | Used by user commands; not public |
| `get_current_view()` | `→ View?` | Returns the active Diffview view |

### `require("diffview.api")` — selections API

| Function | Notes |
|----------|-------|
| `get_entries(view?)` | Returns selected DiffEntry objects |

---

## 3. Config Structure (`setup()`)

Defined in `lua/diffview/config.lua`.  Current top-level keys:

| Key | Type | Notes |
|-----|------|-------|
| `diff_binaries` | `boolean` | Show binary diffs |
| `enhanced_diff_hl` | `boolean` | Use enhanced diff highlights |
| `git_cmd` | `string[]` | Git executable and base flags |
| `git_log_cmd` | `string[]` | Git log command |
| `hg_cmd` | `string[]` | Mercurial executable |
| `use_icons` | `boolean` | Enable devicon/mini.icons |
| `watch_index` | `boolean` | Auto-refresh on git index change |
| `signs` | table | Fold, section open/close signs |
| `view` | table | Layout config per view type |
| `file_panel` | table | File panel appearance |
| `file_history_panel` | table | History panel appearance |
| `commit_log_panel` | table | Commit log panel appearance |
| `default_args` | table | Default CLI args per command |
| `hooks` | table | Lifecycle hooks (callbacks) |
| `keymaps` | table | Per-layout keymap tables (~98 entries) |

> [!WARNING]
> The `keymaps` table is scheduled for replacement in Phase 3.
> The new API will be `keymaps = { preset = "minimal", custom = { ["action.id"] = "<keys>" } }`.

---

## 4. User Autocmds

Emitted via `config.user_emitter` after the corresponding internal event.

| Autocmd | When |
|---------|------|
| `DiffviewViewOpened` | After a view is fully initialised and displayed |
| `DiffviewViewClosed` | After a view is closed and resources freed |
| `DiffviewViewEnter` | On entering a Diffview tabpage |
| `DiffviewViewLeave` | On leaving a Diffview tabpage |
| `DiffviewDiffBufRead` | After a diff buffer is loaded |
| `DiffviewDiffBufWinEnter` | After entering a diff buffer window |

Listen with:
```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "DiffviewViewOpened",
  callback = function(ev) ... end,
})
```

---

## 5. Notable Internal Globals (not public API, but widely referenced in tests)

| Global | Purpose |
|--------|---------|
| `DiffviewGlobal.logger` | Debug logger (level controlled by `DEBUG_DIFFVIEW` env) |
| `DiffviewGlobal.emitter` | Internal `EventEmitter` instance |
| `DiffviewGlobal.state` | Active views and misc runtime state |
| `DiffviewGlobal.debug_level` | Integer; set from `$DEBUG_DIFFVIEW` |

> [!NOTE]
> `DiffviewGlobal` is scheduled for removal in Phase 2.
> The replacement is a module-local `RuntimeContext` + explicit `Store`.

---

## 6. `require("diffview.config").actions` Namespace

`config.actions` exposes the same action functions as `actions.lua` but
pre-bound to the current config context.  This is how keymap callbacks
reference actions (e.g., `config.actions.next_entry`).

This namespace is an **internal implementation detail**, not a stable public
API, but is referenced by users who define custom keymaps in their config.
It will remain available in Phase 3, renamed to reference ActionRegistry IDs.

---

## Change log for this document

| Date | Change |
|------|--------|
| 2026-09-19 | Initial inventory created (Phase 0 baseline) |
