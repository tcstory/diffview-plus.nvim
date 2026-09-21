-- Regression coverage for the asynchronous open path. Phase 5 removes
-- domain-specific `<Nop>` guards from the shared placeholder; registered
-- actions are gated centrally by ViewShell until the view reports ready.
local config = require("diffview.config")
local helpers = require("diffview.tests.helpers")

local DiffView = require("diffview.scene.views.diff.diff_view").DiffView
local EventEmitter = require("diffview.events").EventEmitter
local File = require("diffview.vcs.file").File
local GitAdapter = require("diffview.vcs.adapters.git").GitAdapter
local GitRev = require("diffview.vcs.adapters.git.rev").GitRev
local RevType = require("diffview.vcs.rev").RevType

local run = helpers.run

---Return the `rhs` of a normal-mode buffer-local mapping for `lhs` on `bufnr`,
---or nil if none exists.
---@param bufnr integer
---@param lhs string
---@return string?
local function buf_nmap_rhs(bufnr, lhs)
  local maps = vim.api.nvim_buf_get_keymap(bufnr, "n")
  for _, m in ipairs(maps) do
    if m.lhs == lhs then
      return m.rhs
    end
  end
  return nil
end

local function make_conflict_repo()
  local repo = helpers.init_repo()
  local path = repo .. "/file.txt"
  local function write(content)
    local f = assert(io.open(path, "w"))
    f:write(content)
    f:close()
  end

  write("a\n")
  run({ "git", "add", "file.txt" }, repo)
  run({ "git", "-c", "commit.gpgsign=false", "commit", "-q", "-m", "base" }, repo)

  -- `init.defaultBranch` may be `main` or `master`; read it back.
  local base_branch = run({ "git", "symbolic-ref", "--short", "HEAD" }, repo)

  run({ "git", "checkout", "-q", "-b", "ours" }, repo)
  write("c\n")
  run({ "git", "-c", "commit.gpgsign=false", "commit", "-q", "-am", "ours" }, repo)
  run({ "git", "checkout", "-q", base_branch }, repo)
  run({ "git", "checkout", "-q", "-b", "theirs" }, repo)
  write("e\n")
  run({ "git", "-c", "commit.gpgsign=false", "commit", "-q", "-am", "theirs" }, repo)
  run({ "git", "checkout", "-q", "ours" }, repo)
  run({ "git", "merge", "theirs" }, repo, { allow_nonzero = true })

  return repo
end

describe("null placeholder ownership", function()
  it("does not inject domain key guards into the shared null buffer", function()
    local bn = File._get_null_buffer()
    assert.is_true(vim.api.nvim_buf_is_loaded(bn))

    for _, lhs in ipairs({ "do", "dp", "1do", "2do", "3do" }) do
      local rhs = buf_nmap_rhs(bn, lhs)
      assert.is_nil(rhs, ("unexpected null-buffer mapping for %q"):format(lhs))
    end
  end)
end)

describe("DiffView:open (issue #262 / #289)", function()
  local orig_emitter, original_config

  before_each(function()
    orig_emitter = DiffviewGlobal.emitter
    DiffviewGlobal.emitter = EventEmitter()
    original_config = vim.deepcopy(config.get_config())
    config.get_config().use_icons = false
  end)

  after_each(function()
    DiffviewGlobal.emitter = orig_emitter
    config.setup(original_config)
  end)

  it("returns promptly on a clean worktree", function()
    local repo = helpers.make_repo()
    local view

    local ok, err = pcall(function()
      view = DiffView({
        adapter = GitAdapter({ toplevel = repo, cpath = repo, path_args = {} }),
        rev_arg = nil,
        path_args = {},
        left = GitRev(RevType.STAGE, 0),
        right = GitRev(RevType.LOCAL),
        options = {},
      })
      local start = vim.uv.hrtime()
      view:open()
      local elapsed_ms = (vim.uv.hrtime() - start) / 1e6
      -- `View:open` no longer waits on anything; the previous 2000 ms
      -- guard could burn the full timeout on a clean worktree (#289).
      assert.is_true(elapsed_ms < 1500, ("open took %.0f ms"):format(elapsed_ms))
    end)

    helpers.close_view(view)
    helpers.cleanup_repo(repo)
    if not ok then
      error(err)
    end
  end)

  it("flips `ready` once `post_open`'s scheduled work runs", function()
    local repo = make_conflict_repo()
    local view

    local ok, err = pcall(function()
      view = DiffView({
        adapter = GitAdapter({ toplevel = repo, cpath = repo, path_args = {} }),
        rev_arg = nil,
        path_args = {},
        left = GitRev(RevType.STAGE, 0),
        right = GitRev(RevType.LOCAL),
        options = {},
      })
      view:open()
      -- `ready` is now an "initial post_open dispatched" gate consumed by
      -- `listeners.lua`'s `tab_enter`; it flips inside a `vim.schedule`.
      assert.is_true(vim.wait(2000, function()
        return view.ready
      end))
    end)

    helpers.close_view(view)
    helpers.cleanup_repo(repo)
    if not ok then
      error(err)
    end
  end)
end)
