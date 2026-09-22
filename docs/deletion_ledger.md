# Deletion Ledger

This file tracks code that is scheduled for removal during the refactor.
Each entry must include: the target module(s), the reason for deletion,
the replacement (or "no replacement — not needed"), and the Phase in which
deletion is expected.

> [!IMPORTANT]
> Do **not** delete any entry from this ledger without either completing the
> removal or explicitly deciding to keep the code.  When code is deleted,
> mark the entry ✅ and record the commit SHA.

---

## Legend

| Symbol | Meaning |
|--------|---------|
| 🔴 | Scheduled for deletion |
| 🟡 | Partially replaced; old code still active |
| ✅ | Deleted (record SHA) |
| ⬜ | Under investigation (no decision yet) |

---

## Phase 1 — Runtime & stable API consolidation

### `vim.loop` alias in p4 adapter

| Field | Value |
|-------|-------|
| **Status** | ✅ Deleted |
| **Files** | `lua/diffview/vcs/adapters/p4/init.lua` lines 28, 94 |
| **Reason** | `vim.loop` is a deprecated alias for `vim.uv`; using the alias emits warnings in Neovim 0.12+. |
| **Replacement** | `vim.uv` directly |
| **Phase** | 1 |
| **Deleted in** | commit `01d6ba7` (refactor(inline_diff,view): Phase 1 stable API migrations) |

### `nvim__ns_set` experimental API in `inline_diff.lua`

| Field | Value |
|-------|-------|
| **Status** | ✅ Deleted |
| **Files** | `lua/diffview/scene/inline_diff.lua` — entire ns_set branch removed |
| **Reason** | `nvim__*` APIs are experimental and explicitly banned by the refactor plan. The stable `nvim_win_add_ns`/`nvim_win_remove_ns` pair is not available in 0.12.x patch series (0.12.41); capability-gated via `WIN_SCOPE_SUPPORTED`. |
| **Replacement** | Stable `nvim_win_add_ns`/`nvim_win_remove_ns` (capability-gated); graceful fallback + warning when not available |
| **Phase** | 1 |
| **Deleted in** | commit `01d6ba7` (refactor(inline_diff,view): Phase 1 stable API migrations) |

### Self-built `Job` / `MultiJob` / `job_utils.lua`

| Field | Value |
|-------|-------|
| **Status** | 🟡 In progress — wrapper created, adapter migration pending |
| **Files** | `lua/diffview/job.lua`, `lua/diffview/multi_job.lua`, `lua/diffview/job_utils.lua` |
| **Reason** | Predates `vim.system()`.  The abstraction leaks libuv handles, has no unified cancellation, and requires per-call close guard.  `vim.system()` provides stdout/stderr streaming, stdin, timeout, kill, and exit-code in one call. |
| **Replacement** | `lua/diffview/runtime/process.lua` (Phase 1 deliverable) |
| **Phase** | 1 |
| **Deleted in** | — (pending adapter migration) |

---

## Phase 2 — Application state & lifecycle

### `DiffviewGlobal` mutable global singleton

| Field | Value |
|-------|-------|
| **Status** | ✅ Business logic fully migrated |
| **Files** | All 25 non-test modules — migrated to `require("diffview.runtime.context")` |
| **Reason** | A single mutable global makes unit testing impossible without a real Neovim session, and couples all modules to the boot order. |
| **Replacement** | `lua/diffview/runtime/context.lua` — module-level context with `logger`, `emitter`, `debug_level`, `state` |
| **Phase** | 2 |
| **Deleted in** | `_G.DiffviewGlobal` still constructed in `bootstrap.lua` for test isolation compatibility; full `_G` removal in Phase 2C |
| **Commits** | `e798dc2` (Phase 2A), `37b7e29` (Phase 2B) |

### Arbitrary-string `EventEmitter`

| Field | Value |
|-------|-------|
| **Status** | 🟡 In progress — emitter access migrated to ctx; typed action IDs in Phase 3 |
| **Files** | `lua/diffview/events.lua`, all `ctx.emitter:emit(...)` call sites |
| **Reason** | String-keyed events have no static type, no payload schema, and produce invisible coupling between emitters and listeners.  Replacing with explicit typed event/action tables makes data flow auditable. |
| **Replacement** | Explicit action types in `lua/diffview/runtime/action_registry.lua` (Phase 3 deliverable) |
| **Phase** | 2 (emitter infrastructure); Phase 3 (action wiring) |
| **Deleted in** | — |

---

## Phase 3 — ActionRegistry & minimal keymaps

### Monolithic `config.lua` keymap arrays (≈98 action mappings)

| Field | Value |
|-------|-------|
| **Status** | ✅ Replaced — minimal/none presets and action-ID wiring active |
| **Files** | `lua/diffview/config.lua` (approx. lines with `keymaps.*` table entries) |
| **Reason** | The same action is declared separately for each layout, leading to duplication and divergence.  The refactor uses a single `ActionRegistry` entry per action; keymaps reference the action ID. |
| **Replacement** | `lua/diffview/runtime/action_registry.lua`; all built-ins, factory variants and UI surfaces use action IDs |
| **Phase** | 3 |
| **Deleted in** | commit `d9da23d` (Phase 3 completion) |

### Monolithic `actions.lua` (~1300 lines)

| Field | Value |
|-------|-------|
| **Status** | ✅ Split into domain declaration modules |
| **Files** | `lua/diffview/actions.lua` |
| **Reason** | All actions in one file with no separation of concerns.  Splitting into domain modules (diff, history, merge, navigation, layout, file) makes each action's preconditions, side effects and tests self-contained. |
| **Replacement** | `lua/diffview/actions/{diff,history,merge,navigation,layout,file,view}.lua`; `actions.lua` is a compatibility facade |
| **Phase** | 3 |
| **Deleted in** | commit `d9da23d` (Phase 3 completion) |

---

## Phase 4 — UI component, Renderer & Router

### Per-button `_G` callback functions

| Field | Value |
|-------|-------|
| **Status** | ✅ Replaced — one namespaced router callback remains |
| **Files** | `lua/diffview/scene/views/diff/merge_view.lua`, `lua/diffview/ui/router.lua` |
| **Reason** | Each button using a unique global function name pollutes `_G`, cannot be garbage-collected before the UI is destroyed, and makes it impossible to audit dangling callbacks. |
| **Replacement** | Single namespaced `UIRouter` global; all components register with `component_id` |
| **Phase** | 4 |
| **Deleted in** | Phase 4 completion commit |

---

## Phase 5 — View, Layout & buffer ownership

### Deep inheritance in `View` / `Layout` / `Window` hierarchy

| Field | Value |
|-------|-------|
| **Status** | ✅ Ownership replaced; dispatch facades retained until final OOP removal |
| **Files** | `lua/diffview/scene/view.lua`, `lua/diffview/scene/layout.lua`, `lua/diffview/scene/window.lua`, layout subclasses under `lua/diffview/scene/layouts/` |
| **Reason** | Inheritance chains make it hard to understand which class handles which concern.  Composition via `ViewShell`, `LayoutSpec`, `BufferLease`, and `WindowLease` gives explicit ownership and testable sub-units. |
| **Replacement** | `lua/diffview/ui/{view_shell,layout_spec,layout_engine,buffer_lease,window_lease}.lua` |
| **Phase** | 5 |
| **Deleted in** | Phase 5 completion commit (null-buffer guard and inherited ownership responsibilities); class-dispatch facade tracked for Phase 10 |

---

## Phase 6 — VCS adapter ports

### Adapter identity checks in UI and action surfaces

| Field | Value |
|-------|-------|
| **Status** | ✅ Replaced |
| **Files** | `lua/diffview/lib.lua`, `lua/diffview/actions/`, `lua/diffview/scene/views/diff/diff_view.lua` |
| **Reason** | UI code coupled to Git/Hg classes made every new adapter require presentation-layer branches and exposed unsupported actions. |
| **Replacement** | Declarative `vcs.Capability` sets plus adapter-owned query methods returning structured results. |
| **Phase** | 6 |
| **Deleted in** | Phase 6 completion commit |

### Monolithic Git command and parser responsibilities

| Field | Value |
|-------|-------|
| **Status** | ✅ Split; compatibility methods remain on `GitAdapter` |
| **Files** | `lua/diffview/vcs/adapters/git/init.lua` |
| **Reason** | Mixing argv construction, process execution, parsing, and presentation made path safety and parser testing difficult to audit. |
| **Replacement** | Pure `git/{status,history,merge,stage}.lua` ports and shared `vcs/path_args.lua`; adapter methods delegate while existing call sites migrate. |
| **Phase** | 6 |
| **Deleted in** | Phase 6 completion commit (duplicated builders/parsers); remaining facade removal is tracked for Phase 10 |

---

## Phase 7 — DiffView and file panel

### File-panel-owned review and current-entry state

| Field | Value |
|-------|-------|
| **Status** | ✅ Replaced; read aliases retained for integrations until Phase 10 |
| **Files** | `lua/diffview/scene/views/diff/{diff_view,file_panel,listeners}.lua` |
| **Reason** | Files, current entry, reviewed keys, hide mode, and filtering were mutated independently by the view and panel, making refresh and navigation races difficult to reason about. |
| **Replacement** | `DiffStore` owns the state and exposes explicit mutation/subscription methods; panel fields are projections. |
| **Phase** | 7 |
| **Deleted in** | Phase 7 completion commit (direct production mutations); compatibility aliases scheduled for Phase 10 |

### External listeners calling `update_files` directly

| Field | Value |
|-------|-------|
| **Status** | ✅ Replaced for index and GitSigns sources |
| **Files** | `lua/diffview/scene/views/diff/diff_view.lua` |
| **Reason** | A raw refresh call loses the source and lets external callbacks bypass the same command boundary used by actions. |
| **Replacement** | Typed `DiffCommand` refresh intents with `user`, `index`, `gitsigns`, or `buffer` source metadata. |
| **Phase** | 7 |
| **Deleted in** | Phase 7 completion commit |

---

## Phase 8 — FileHistory

### Pin-local layout subclasses

| Field | Value |
|-------|-------|
| **Status** | ✅ Production dependency removed; compatibility modules retained until Phase 10 |
| **Files** | `lua/diffview/scene/layouts/{diff_1_pinned,diff_1_inline_pinned,diff_2_hor_pinned,diff_2_ver_pinned}.lua` |
| **Reason** | Encoding one view mode in four layout classes multiplied ownership and null-side rules across every orientation. |
| **Replacement** | `FileHistoryStore.view` owns the mode and pinned files; ordinary layout instances receive borrowed-symbol state from `FileEntry`. |
| **Phase** | 8 |
| **Deleted in** | Phase 10 compatibility removal |

### Full component rebuild on streamed history batches

| Field | Value |
|-------|-------|
| **Status** | ✅ Replaced |
| **Files** | `lua/diffview/scene/views/file_history/file_history_panel.lua` |
| **Reason** | Recreating every component on each streamed batch made long histories scale poorly and invalidated component identity. |
| **Replacement** | Stable history component root with append-only entry component creation during a query generation. |
| **Phase** | 8 |
| **Deleted in** | Phase 8 completion commit |

---

## Phase 10 — Final cleanup

### Self-built OOP framework (`oop.lua`, `Object:extend`, etc.)

| Field | Value |
|-------|-------|
| **Status** | 🔴 Scheduled |
| **Files** | `lua/diffview/oop.lua`, all classes that call `ClassName:extend()` |
| **Reason** | The OOP framework predates Neovim's `vim.iter`, LuaLS annotations and modern Lua idioms.  It adds a non-standard class mechanism that is invisible to LuaLS and confuses new contributors.  The refactor uses plain Lua tables and `---@class` annotations throughout. |
| **Replacement** | Plain Lua modules with LuaLS `---@class` / `---@field` annotations |
| **Phase** | 10 (after all classes have been replaced) |
| **Deleted in** | — |

### Self-built coroutine scheduler (`async.lua`, `Waitable`)

| Field | Value |
|-------|-------|
| **Status** | 🔴 Scheduled |
| **Files** | `lua/diffview/async.lua`, `lua/diffview/control.lua` |
| **Reason** | The scheduler predates `vim.system()` and does not integrate with Neovim's own `vim.schedule`/`vim.defer_fn` boundary cleanly.  Cancellation and close-race are each caller's responsibility.  `EffectScope` + `vim.system` provide cleaner cancellation without a custom scheduler. |
| **Replacement** | `lua/diffview/app/effect_scope.lua`; `vim.system()` for subprocess management |
| **Phase** | 10 (blocked on all callers being migrated) |
| **Deleted in** | — |

---

## Investigation queue

These items need a caller-count / usage analysis before a decision is made.

| Module | Concern |
|--------|---------|
| `lua/diffview/path.lua` (`PathLib`) | Large utility; partially superseded by `vim.fs.*`.  Identify which methods have no `vim.fs` equivalent. |
| `lua/diffview/diff.lua` | Uses `vim.diff` (old alias?).  Check if `vim.text.diff` can replace fully. |
| `lua/diffview/scene/inline_diff.lua` UTF-8 helpers | Check if `vim.str_utf_pos` replaces all hand-written iterators. |
| `lua/diffview/ffi.lua` | Determine which FFI calls are still required under 0.12 and whether stable API alternatives exist. |
| Vimscript completion bridge | Identify remaining `:command -complete=customlist,...` sites; check if Lua completion callbacks cover them. |
