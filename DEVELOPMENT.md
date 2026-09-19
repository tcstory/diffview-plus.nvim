# diffview-plus.nvim — Developer Guide

> Phase: 0 (Baseline)  
> Target Neovim: ≥ 0.12.0  
> Last updated: 2026-09-19

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

This section walks a single user action ("stage file") from keypress to git
command, so you can quickly orient yourself in the codebase.

> **Note**: This walk-through reflects the **pre-refactor** architecture.
> The module names and call sites will change as each Phase progresses; this
> document will be updated after each Phase.

1. **Keymap** — `lua/diffview/config.lua` maps `<leader>s` to `actions.stage_all`.
2. **Action** — `lua/diffview/actions.lua` `stage_all()` resolves the current
   view via `require("diffview").get_current_view()`.
3. **View** — `DiffView:stage_all()` calls the active VCS adapter.
4. **Adapter** — `lua/diffview/vcs/adapters/git/init.lua` builds a
   `git add` argument list and spawns a `Job` via `lua/diffview/job.lua`.
5. **Job** — wraps `vim.uv.spawn`; completion callback dispatches an event.
6. **Event** — `DiffviewGlobal.emitter:emit("REFRESH")` triggers a panel
   re-render.

> **Tracing tip**: set `DEBUG_DIFFVIEW=10` in your shell before launching
> Neovim to enable verbose logging at level 10 (rendering & async).
> Output goes to `DiffviewGlobal.logger`.

---

## 6. Debug

### Verbose logging

```bash
DEBUG_DIFFVIEW=10 nvim
```

Log levels:  
`0` = silent · `1` = normal · `5` = loading · `10` = rendering & async

### Inspect global state

In any Neovim session:

```vim
:lua print(vim.inspect(DiffviewGlobal.state))
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

Baseline benchmarks (Phase 0) for the reference dataset are recorded in
`docs/adr/adr-000-phase0-baselines.md`.

---

## 8. Architecture overview (Phase 0 baseline)

```
plugin/diffview.vim          -- Vimscript shim; loads bootstrap + commands
lua/diffview/bootstrap.lua   -- Global init, version guard, EventEmitter
lua/diffview/config.lua      -- ~1900-line monolithic config + keymap setup
lua/diffview/actions.lua     -- ~1300-line action implementations
lua/diffview/scene/          -- View / Layout / Panel / Window hierarchy
lua/diffview/vcs/            -- Git / JJ / Hg / P4 adapters
lua/diffview/async.lua       -- Self-rolled coroutine scheduler (Waitable)
lua/diffview/job.lua         -- libuv process wrapper (pre-vim.system era)
lua/diffview/tests/          -- Plenary-based functional tests
```

The current architecture is **hub-and-spoke** around `DiffviewGlobal` and a
shared `EventEmitter`.  The refactor plan (`REFACTOR_PLAN.md`) incrementally
replaces this with layered Store / EffectScope / ActionRegistry / UIRouter.

Each Phase adds a `docs/adr/` entry describing what changed, which Neovim APIs
were used, and what was deleted.

---

## 9. Making a contribution

1. Branch from `main`.
2. One logical change per commit; include tests and docs.
3. Run `make check` before pushing.
4. For refactor Phases, follow the task checklist in `REFACTOR_PLAN.md` and
   update the Phase's ADR in `docs/adr/`.
5. Breaking changes belong in `docs/deletion_ledger.md` with a migration note.
