# diffview-plus.nvim — Developer Guide

> Phase: 10 (Final architecture)
> Target Neovim: ≥ 0.12.0
> Last updated: 2026-09-22

This guide is the starting point for anyone contributing to diffview-plus.nvim.
It covers the minimum setup needed to run the plugin from source, execute tests,
trace a single action through the call graph, and profile a slow operation.

---

## 1. Prerequisites

| Tool                  | Minimum version | Purpose                          |
|-----------------------|-----------------|----------------------------------|
| Neovim                | 0.12.0          | Runtime                          |
| Git                   | 2.31.0          | VCS adapter + test fixtures      |
| Jujutsu (`jj`)       | 0.38.0          | JJ adapter tests (optional)      |
| Mercurial (`hg`)      | 5.4.0           | Hg adapter tests (optional)      |
| `lua-language-server` | any stable      | `make type-check` (optional)     |
| `stylua`              | any stable      | `make fmt` (optional)            |
| `jq`                  | any             | `make type-check` config gen     |

Plenary.nvim is fetched automatically by `scripts/test_init.lua` when running
`make test`; you do **not** need to install it separately.

---

## 2. Load the plugin from source (no package manager)

Add to your `init.lua` (or `init.vim` equivalent):

```lua
-- Replace /path/to/diffview-plus.nvim with the actual clone location.
vim.opt.runtimepath:prepend("/path/to/diffview-plus.nvim")
require("diffview").setup()
```

Then open Neovim and run `:checkhealth diffview` to verify the plugin loaded
and at least one VCS adapter is available.

---

## 3. Run tests

```bash
# All tests
make test

# A single file
TEST_PATH=lua/diffview/tests/functional/diff_view_spec.lua make test

# All tests matching a Lua pattern (uses Plenary's built-in filter)
TEST_PATH=lua/diffview/tests/functional/ make test
```

Tests use [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)'s Busted
runner in headless mode (`nvim --headless`).  
See `scripts/test_init.lua` for how the runtime path and dependencies are set up.

### Skipping VCS-specific tests when the binary is missing

Tests for optional VCS tools (Hg, P4, JJ) call `helpers.skip_if_missing()` at
the top of the spec file.  You can write the same guard in new specs:

```lua
local helpers = require("diffview.tests.helpers")
helpers.skip_if_missing("hg")   -- skip the file if `hg` is not on PATH
```

---

## 4. Static analysis

```bash
# StyLua formatting check (does not rewrite files; exit 1 on diff)
stylua --check lua/

# Apply formatting
stylua lua/

# LuaLS type-check (source files; fails on any diagnostic)
make type-check

# LuaLS type-check (test files; advisory, does not fail CI)
make type-check-tests

# Config schema validation
make check-config-schema
```

`make check` runs all static checks and the test suite in one command:

```bash
make check
```

---

## 5. Trace one action end-to-end

This section follows the `diff.toggle_stage_entry` action from UI input to a
Git process and back to the projected file list.

1. **Input** — a toolbar component, palette item, click, or custom keymap carries
   the stable action ID `diff.toggle_stage_entry`.
2. **Route** — `lua/diffview/ui/router.lua` resolves the component and dispatches
   the ID through `runtime/action_registry.lua` with the current view context.
3. **Action** — `lua/diffview/actions/diff.lua` declares metadata and capability
   requirements; the implementation in `actions/impl.lua` emits a typed command.
4. **Adapter port** — the command calls the adapter's stage capability. Git
   delegates argv construction to `vcs/adapters/git/stage.lua`.
5. **Process** — `runtime/process_task.lua` runs the argv list through
   `vim.system()`; the owning view's `EffectScope` can cancel it on close.
6. **Projection** — completion dispatches one refresh intent. The `DiffStore`
   accepts only the current generation, then the component renderer patches
   changed buffer lines and extmarks.

> **Tracing tip**: set `DEBUG_DIFFVIEW=10` in your shell before launching
> Neovim to enable verbose logging at level 10 (rendering & async).
> Output goes through the logger owned by `diffview.runtime.context`.

---

## 6. Debug

### Verbose logging

```bash
DEBUG_DIFFVIEW=10 nvim
```

Log levels:  
`0` = silent · `1` = normal · `5` = loading · `10` = rendering & async

### Inspect the current view state

In any Neovim session:

```vim
:lua local v = require("diffview.lib").get_current_view(); print(vim.inspect(v and v.store and v.store.state))
```

### Breakpoint with `vim.print`

For quick inspection, insert `vim.print(my_var)` anywhere; output appears in
the messages area (`:messages`).

---

## 7. Performance profiling

Diffview ships with a lightweight `perf.lua` profiler:

```lua
local Perf = require("diffview.perf")
local p = Perf.PerfTimer("<label>")
-- ... code to measure ...
p:time()    -- record checkpoint
p:spew()    -- print all checkpoints to messages
```

For coarser wall-clock measurement, use `vim.uv.hrtime()`:

```lua
local t0 = vim.uv.hrtime()
-- ... work ...
local ms = (vim.uv.hrtime() - t0) / 1e6
print(string.format("elapsed: %.2f ms", ms))
```

Repeatable scale budgets and their test commands are recorded in
`docs/performance-baselines.md`.

---

## 8. Architecture overview

```
plugin/diffview.lua                 -- user commands and Lua completion
lua/diffview/runtime/               -- process, ownership, progress, actions
lua/diffview/domain/                -- pure merge transaction state
lua/diffview/actions/               -- action declarations by domain
lua/diffview/vcs/                   -- capability ports and adapters
lua/diffview/ui/                    -- components, router, leases, renderer
lua/diffview/scene/views/*/store.lua -- view state and typed commands
lua/diffview/tests/                 -- unit, functional, race, integration tests
```

The dependency flow is input → action → domain/store → projection. Shared
bootstrap services are module-local in `runtime/context.lua`; no mutable `_G`
state is used. See `docs/architecture.md` for all three end-to-end view flows
and `docs/phase3-actions.md` through `docs/phase10-cleanup.md` for the phase
notes.

---

## 9. Making a contribution

1. Branch from `main`.
2. One logical change per commit; include tests and docs.
3. Run `make check` before pushing.
4. For refactor Phases, follow the task checklist in `REFACTOR_PLAN.md` and
   update the Phase's ADR in `docs/adr/`.
5. Breaking changes belong in `docs/deletion_ledger.md` with a migration note.
