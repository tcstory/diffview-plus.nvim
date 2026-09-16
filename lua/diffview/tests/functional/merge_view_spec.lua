local config = require("diffview.config")
local helpers = require("diffview.tests.helpers")
local MergeView = require("diffview.scene.views.diff.merge_view").MergeView
local RevType = require("diffview.vcs.rev").RevType
local vcs = require("diffview.vcs")

local eq = helpers.eq

local function make_conflict_repo()
  local repo = helpers.init_repo()
  helpers.write(repo, "file.txt", { "base" })
  helpers.commit(repo, "base")
  local target_branch = helpers.run({ "git", "branch", "--show-current" }, repo)
  helpers.run({ "git", "branch", "feature" }, repo)
  helpers.write(repo, "file.txt", { "ours" })
  helpers.commit(repo, "ours")
  helpers.run({ "git", "switch", "-q", "feature" }, repo)
  helpers.write(repo, "file.txt", { "theirs" })
  helpers.commit(repo, "theirs")
  helpers.run({ "git", "switch", "-q", target_branch }, repo)
  helpers.system({ "git", "merge", "feature" }, repo, { allow_nonzero = true })
  return repo
end

describe("diffview.scene.views.diff.merge_view", function()
  local repo, view, original_config

  before_each(function()
    original_config = vim.deepcopy(config.get_config())
    config.get_config().use_icons = false
  end)

  after_each(function()
    if view and view.tabpage and vim.api.nvim_tabpage_is_valid(view.tabpage) then
      view:close({ force = true })
    end
    require("diffview.lib").dispose_view(view)
    config.setup(original_config)
    if repo then
      helpers.cleanup_repo(repo)
    end
  end)

  it("constructs a read-only OURS/THEIRS view around an editable virtual Result", function()
    repo = make_conflict_repo()
    local err, adapter = vcs.get_adapter({ top_indicators = { repo } })
    assert.is_nil(err)
    view = MergeView({ adapter = adapter, paths = { "file.txt" } })

    local entry = view.files.conflicting[1]
    eq(RevType.STAGE, entry.layout.a.file.rev.type)
    eq(2, entry.layout.a.file.rev.stage)
    eq(RevType.CUSTOM, entry.layout.b.file.rev.type)
    assert.is_true(entry.layout.b.file.editable)
    eq(RevType.STAGE, entry.layout.c.file.rev.type)
    eq(3, entry.layout.c.file.rev.stage)
    eq(1, entry.merge_conflicts_remaining)
    assert.truthy(table.concat(vim.fn.readfile(repo .. "/file.txt"), "\n"):find("<<<<<<<", 1, true))
  end)

  it(
    "opens a Result buffer with a clickable apply action and commits only after resolution",
    helpers.async_test(function()
      repo = make_conflict_repo()
      local err, adapter = vcs.get_adapter({ top_indicators = { repo } })
      assert.is_nil(err)
      view = MergeView({ adapter = adapter, paths = { "file.txt" } })
      view:open()
      vim.wait(2000, function()
        local session_entry = view.merge_session:get("file.txt")
        return view.ready
          and view.cur_entry
          and view.cur_entry.layout.b.file:is_valid()
          and session_entry
          and session_entry.bufnr ~= nil
      end, 10)

      local result_file = view.cur_entry.layout.b.file
      assert.is_true(vim.bo[result_file.bufnr].modifiable)
      for _, symbol in ipairs({ "a", "b", "c" }) do
        local winhl = vim.wo[view.cur_layout[symbol].id].winhl
        assert.truthy(winhl:find("DiffChange:Normal", 1, true))
        assert.truthy(winhl:find("DiffText:DiffviewDiffText", 1, true))
      end
      assert.truthy(vim.wo[view.panel.winid].winbar:find("[ ◀ ] Hide files", 1, true))
      assert.is_nil(result_file.winbar:find("DiffviewMergePanelClick", 1, true))
      local ours_at = assert(result_file.winbar:find("[ OURS ]", 1, true))
      local apply_at = assert(result_file.winbar:find("[ APPLY ]", 1, true))
      local counts_at = assert(result_file.winbar:find("FILE 1/1 | ALL 1/1", 1, true))
      assert.is_true(ours_at < apply_at and apply_at < counts_at)
      eq(1, view.cur_entry.merge_conflicts_remaining)

      assert.is_true(view.panel:is_open())
      local expanded_width = vim.api.nvim_win_get_width(view.panel.winid)
      _G.DiffviewMergePanelClick()
      assert.is_true(view.panel:is_open())
      eq(5, vim.api.nvim_win_get_width(view.panel.winid))
      assert.truthy(vim.wo[view.panel.winid].winbar:find("[ ▶ ]", 1, true))
      assert.is_nil(result_file.winbar:find("DiffviewMergePanelClick", 1, true))
      _G.DiffviewMergePanelClick()
      assert.is_true(view.panel:is_open())
      eq(expanded_width, vim.api.nvim_win_get_width(view.panel.winid))
      assert.truthy(vim.wo[view.panel.winid].winbar:find("[ ◀ ] Hide files", 1, true))

      assert.is_false(view:can_close({ force = false }))

      view:choose_all_conflicts("ours")
      eq(0, view.merge_session:counts())
      eq(0, view.cur_entry.merge_conflicts_remaining)
      assert.is_true(view:apply_all())
      eq({ "ours" }, vim.fn.readfile(repo .. "/file.txt"))
    end)
  )
end)
