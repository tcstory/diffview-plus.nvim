local config = require("diffview.config")
local helpers = require("diffview.tests.helpers")
local Diff1 = require("diffview.scene.layouts.diff_1").Diff1
local Diff3Hor = require("diffview.scene.layouts.diff_3_hor").Diff3Hor
local Diff4Mixed = require("diffview.scene.layouts.diff_4_mixed").Diff4Mixed
local MergeView = require("diffview.scene.views.diff.merge_view").MergeView
local RevType = require("diffview.vcs.rev").RevType
local vcs = require("diffview.vcs")
local router = require("diffview.ui.router")

local eq = helpers.eq

local function route_id(winbar, label)
  local escaped = vim.pesc(label)
  return tonumber(assert(winbar:match("%%(%d+)@v:lua%.DiffviewUIRouter@" .. escaped)))
end

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
    assert.equals(0, router.size())
    router._reset()
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

  it("honours the configured initial merge layout", function()
    repo = make_conflict_repo()
    config.get_config().view.merge_tool.layout = "diff4_mixed"
    local err, adapter = vcs.get_adapter({ top_indicators = { repo } })
    assert.is_nil(err)

    view = MergeView({ adapter = adapter, paths = { "file.txt" } })
    assert.is_true(view.files.conflicting[1].layout:instanceof(Diff4Mixed))
  end)

  it("does not propagate RESULT data producers to stage sides during layout conversion", function()
    repo = make_conflict_repo()
    local err, adapter = vcs.get_adapter({ top_indicators = { repo } })
    assert.is_nil(err)

    view = MergeView({ adapter = adapter, paths = { "file.txt" } })
    local entry = view.files.conflicting[1]
    entry:convert_layout(Diff1)
    entry:convert_layout(Diff3Hor)

    assert.is_nil(entry.layout.a.file.get_data)
    assert.is_nil(entry.layout.c.file.get_data)
    eq(RevType.STAGE, entry.layout.a.file.rev.type)
    eq(RevType.STAGE, entry.layout.c.file.rev.type)
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
      assert.truthy(result_file.winbar:find("[ ◀ ]", 1, true))
      assert.truthy(result_file.winbar:find("[ ▶ ]", 1, true))
      assert.truthy(result_file.winbar:find("v:lua.DiffviewUIRouter", 1, true))
      local apply_at = assert(result_file.winbar:find("[ APPLY ]", 1, true))
      local counts_at = assert(result_file.winbar:find("FILE 1/1 unresolved | ALL 1/1", 1, true))
      assert.is_true(apply_at < counts_at)
      eq(1, view.cur_entry.merge_conflicts_remaining)

      -- Test clicking [ ▶ ] and [ ◀ ] winbar buttons
      local next_res = router.dispatch_id(route_id(result_file.winbar, "[ ▶ ]"))
      eq(1, next_res and next_res.current)
      local prev_res = router.dispatch_id(route_id(result_file.winbar, "[ ◀ ]"))
      eq(1, prev_res and prev_res.current)

      assert.is_nil(result_file.winbar:find("[ OURS ]", 1, true))
      assert.is_nil(result_file.winbar:find("[ THEIRS ]", 1, true))

      assert.is_true(view.panel:is_open())
      local expanded_width = vim.api.nvim_win_get_width(view.panel.winid)
      local wb_before = vim.api.nvim_win_get_width(view.cur_layout.b.id)
      local wc_before = vim.api.nvim_win_get_width(view.cur_layout.c.id)

      router.dispatch_id(route_id(vim.wo[view.panel.winid].winbar, "[ ◀ ] Hide files"))
      assert.is_true(view.panel:is_open())
      eq(5, vim.api.nvim_win_get_width(view.panel.winid))
      assert.truthy(vim.wo[view.panel.winid].winbar:find("[ ▶ ]", 1, true))
      assert.is_nil(result_file.winbar:find("DiffviewMergePanelClick", 1, true))

      local wa_after = vim.api.nvim_win_get_width(view.cur_layout.a.id)
      local wb_after = vim.api.nvim_win_get_width(view.cur_layout.b.id)
      local wc_after = vim.api.nvim_win_get_width(view.cur_layout.c.id)
      assert.is_true(wb_after > wb_before)
      assert.is_true(wc_after > wc_before)
      assert.is_true(math.abs(wa_after - wb_after) <= 2)
      assert.is_true(math.abs(wb_after - wc_after) <= 2)

      router.dispatch_id(route_id(vim.wo[view.panel.winid].winbar, "[ ▶ ]"))
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

  it(
    "resolves conflicts when clicking inline [ OURS ] and [ THEIRS ] buttons",
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

      local entry = view.cur_entry
      local session_entry = view.merge_session:get("file.txt")
      local conflict = session_entry.conflicts[1]
      local start_row = view.merge_session:_range(session_entry, conflict)
      local target_line = start_row + 1
      local result_win = view.cur_layout.b.id
      local wininfo = vim.fn.getwininfo(result_win)[1]
      local textoff = wininfo and wininfo.textoff or 0
      local status_w = vim.fn.strdisplaywidth((" Unresolved %d "):format(conflict.id))

      -- Clicking the actual code line (screenpos.row) should not resolve conflict and should allow normal click
      local sp = vim.fn.screenpos(result_win, target_line, 1)
      local orig_getmousepos = vim.fn.getmousepos
      if sp and sp.row > 0 then
        conflict.resolved = false
        conflict.choice = nil
        view.merge_session:_place_mark(session_entry, conflict)

        vim.fn.getmousepos = function()
          return {
            winid = result_win,
            line = target_line,
            wincol = textoff + status_w + 3,
            column = 1,
            screenrow = sp.row, -- on the code line, NOT the virtual line
          }
        end
        local handled = router.dispatch_buffer("mouse", session_entry.bufnr)
        eq(false, conflict.resolved)
        eq(nil, conflict.choice)
        eq(false, handled or false)
      end

      -- Simulate click on [ OURS ] button on the virtual line above the conflict
      local virt_screenrow = (sp and sp.row > 0) and sp.row - 1 or 0
      vim.api.nvim_set_current_win(view.cur_layout.a.id)
      vim.fn.getmousepos = function()
        return {
          winid = result_win,
          line = target_line,
          wincol = textoff + status_w + 3, -- inside [ OURS ] at front of line
          column = 1,
          screenrow = virt_screenrow > 0 and virt_screenrow or nil,
        }
      end

      local handled_ours = router.dispatch_buffer("mouse", session_entry.bufnr)
      vim.fn.getmousepos = orig_getmousepos

      eq(true, handled_ours)
      assert.is_true(vim.wait(1000, function()
        return conflict.resolved and conflict.choice == "ours"
      end))
      eq(true, conflict.resolved)
      eq("ours", conflict.choice)
      eq(0, session_entry.file_entry.merge_conflicts_remaining)

      -- Now switch to THEIRS by clicking [ THEIRS ]
      local resolved_status_w = vim.fn.strdisplaywidth(" ✔ ours ")
      local ours_w = vim.fn.strdisplaywidth("[ ✔ OURS ]")
      vim.fn.getmousepos = function()
        return {
          winid = result_win,
          line = target_line,
          wincol = textoff + resolved_status_w + ours_w + 5, -- inside [ THEIRS ] at front of line
          column = 1,
          screenrow = virt_screenrow > 0 and virt_screenrow or nil,
        }
      end

      local handled_theirs = router.dispatch_buffer("mouse", session_entry.bufnr)
      vim.fn.getmousepos = orig_getmousepos

      eq(true, handled_theirs)
      assert.is_true(vim.wait(1000, function()
        return conflict.choice == "theirs"
      end))
      eq(true, conflict.resolved)
      eq("theirs", conflict.choice)
      eq(0, session_entry.file_entry.merge_conflicts_remaining)
    end)
  )

  it(
    "blocks stage-all and unstage-all mutations in a transactional merge view",
    helpers.async_test(function()
      repo = make_conflict_repo()
      local err, adapter = vcs.get_adapter({ top_indicators = { repo } })
      assert.is_nil(err)
      local add_called, reset_called = false, false
      adapter.add_files = function()
        add_called = true
        return true
      end
      adapter.reset_files = function()
        reset_called = true
        return true
      end

      view = MergeView({ adapter = adapter, paths = { "file.txt" } })
      view:open()
      assert.is_true(vim.wait(2000, function()
        return view.ready and view.cur_entry ~= nil
      end, 10))

      view.emitter:emit("stage_all")
      view.emitter:emit("unstage_all")
      assert.is_false(add_called)
      assert.is_false(reset_called)
    end)
  )
end)
