# ADR-000: Phase 0 — Baseline, Neovim 0.12 Minimum Version, and Quality Gate

| Field       | Value           |
|-------------|-----------------|
| **Date**    | 2026-09-19      |
| **Phase**   | 0               |
| **Status**  | Accepted        |

---

## Context

diffview-plus.nvim was built on a Neovim 0.10 baseline.  The refactor plan
(`REFACTOR_PLAN.md`) targets Neovim 0.12 stable APIs exclusively:

| API goal               | Available in 0.12? |
|------------------------|--------------------|
| `vim.system()`         | Yes (0.10+)        |
| `vim.uv`               | Yes (replaces `vim.loop`) |
| `vim.fs.root`          | Yes                |
| `vim.text.diff`        | Yes                |
| `vim.str_utf_pos`      | Yes                |
| `nvim_open_tabpage()`  | Yes                |
| `vim.ui.open`          | Yes                |
| `vim.async`            | **No** (not yet stable in 0.12.4) |
| `nvim_win_add_ns/remove_ns` | **No** (not in 0.12.4) |

Raising the minimum version enables future Phases to use these APIs without
wrapping them in version-guards, and removes the obligation to maintain
0.10-compatible code paths.

## Decision

1. **Minimum Neovim version = 0.12.0.**  
   The version guard in `lua/diffview/bootstrap.lua` and the check in
   `lua/diffview/health.lua` are updated from `nvim-0.10` to `nvim-0.12`.
   `README.md` and `CONTRIBUTING.md` are updated to match.

2. **`make check` is the project-wide quality gate.**  
   It runs, in order: `fmt-check` → `type-check` → `check-config-schema` →
   `test`.  Every Phase must keep `make check` green before merging.

3. **`helpers.skip_if_missing(binary)` is the canonical way to guard
   optional-VCS spec files.**  
   Calling it at the top of a spec file causes the entire file to be
   marked as pending when the named binary is absent from PATH.

4. **`DEVELOPMENT.md` is the entry-point for contributors.**  
   It covers: prerequisites, loading from source, running tests, static
   analysis, end-to-end action trace, debugging and performance profiling.

5. **`docs/adr/` stores Architecture Decision Records.**  
   Every Phase must produce one ADR.  The template is `docs/adr/adr-template.md`.

### Neovim API references

| API / help tag              | Stable in | Used here |
|-----------------------------|-----------|-----------|
| `:h vim.fn.has()`           | all       | version guard |
| `:h vim.health`             | 0.10+     | `:checkhealth diffview` |

## Alternatives considered

| Alternative | Reason rejected |
|-------------|-----------------|
| Keep 0.10 baseline, capability-gate all 0.12 APIs | Doubles test surface and obscures the canonical pattern for new contributors |
| Jump to 0.13/nightly baseline | `vim.async` and `nvim_win_add_ns` are not stable in the 0.12.4 version verified on the development machine |

## Consequences

**Positive:**
- Future Phases can use 0.12 APIs directly without version guards.
- `make check` gives a single command for CI and pre-commit.
- `skip_if_missing()` prevents spurious failures in CI environments
  without Hg/JJ/P4.

**Negative / trade-offs:**
- Users on Neovim 0.10 or 0.11 will see a clear error and must upgrade.
  No compat shim is provided.

**Files changed:**
`lua/diffview/bootstrap.lua`, `lua/diffview/health.lua`, `README.md`,
`CONTRIBUTING.md`, `Makefile`, `lua/diffview/tests/helpers.lua`,
`DEVELOPMENT.md`, `docs/adr/adr-000-phase0-baselines.md`

---

## Developer note

This ADR covers only infrastructure changes; no runtime behaviour was altered.

To verify the version guard locally:

```bash
# Should print the error message and exit non-zero on Neovim < 0.12
nvim --headless -u NONE -c "lua if vim.fn.has('nvim-0.12') ~= 1 then print('old') else print('ok') end" -c "qa"
```

To run the full quality gate:

```bash
make check
```

`make check` depends on `stylua`, `lua-language-server`, `jq` and `nvim`
being on PATH.  If `lua-language-server` or `stylua` are absent, `make test`
alone will still validate runtime behaviour.
