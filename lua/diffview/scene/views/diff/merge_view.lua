local lazy = require("diffview.lazy")

local DiffView = lazy.access("diffview.scene.views.diff.diff_view", "DiffView") ---@type DiffView|LazyModule
local File = lazy.access("diffview.vcs.file", "File") ---@type vcs.File|LazyModule
local FileEntry = lazy.access("diffview.scene.file_entry", "FileEntry") ---@type FileEntry|LazyModule
local MergeSession = lazy.access("diffview.merge_session", "MergeSession") ---@type MergeSession|LazyModule
local NullDiffView = lazy.access("diffview.scene.views.diff.null_diff_view", "NullDiffView") ---@type NullDiffView|LazyModule
local RevType = lazy.access("diffview.vcs.rev", "RevType") ---@type RevType|LazyModule
local StandardView = lazy.access("diffview.scene.views.standard.standard_view", "StandardView") ---@type StandardView|LazyModule
local View = lazy.access("diffview.scene.view", "View") ---@type View|LazyModule
local utils = lazy.require("diffview.utils") ---@module "diffview.utils"
local router = require("diffview.ui.router")

local api = vim.api

local M = {}

local NullDiffViewClass = NullDiffView.__get()

---@class MergeView : NullDiffView
---@operator call : MergeView
---@field merge_session MergeSession
---@field applied boolean
---@field panel_collapsed boolean
---@field panel_expanded_width? integer
---@field _winbar_routes? table
local MergeView = { __name = "MergeView" }
MergeView.__index = MergeView
MergeView.super_class = NullDiffViewClass
setmetatable(MergeView, {
  __index = NullDiffViewClass,
  __call = function(_, ...)
    local view = setmetatable({ class = MergeView }, MergeView)
    view:init(...)
    return view
  end,
})

---@param opt { adapter: GitAdapter, paths: string[] }
function MergeView:init(opt)
  local ours = opt.adapter.Rev(RevType.STAGE, 2)
  local theirs = opt.adapter.Rev(RevType.STAGE, 3)
  local base = opt.adapter.Rev(RevType.STAGE, 1)
  local result_rev = opt.adapter.Rev(RevType.CUSTOM)

  self.merge_session = MergeSession(opt.adapter, opt.paths)
  self.applied = false
  self.panel_collapsed = false

  NullDiffViewClass.init(self, {
    adapter = opt.adapter,
    path_args = opt.paths,
    rev_arg = nil,
    left = ours,
    right = theirs,
    options = {},
  })

  -- Keep the precise DiffText highlight, but remove the broad DiffChange
  -- wash from every merge layout. Conflict state is already shown explicitly
  -- by the Result extmarks and their Unresolved labels.
  for _, layout_key in ipairs({ "diff1", "diff3", "diff4" }) do
    for _, winopts in pairs(self.winopts[layout_key]) do
      winopts.winhl = {
        "DiffAdd:DiffviewDiffAdd",
        "DiffDelete:DiffviewDiffDelete",
        "DiffChange:Normal",
        "DiffText:DiffviewDiffText",
        opt = { method = "prepend" },
      }
    end
  end

  -- DiffView binds its own marker-based `file_open_post` handler while its
  -- constructor is running. Register the Result-aware handler explicitly
  -- afterwards so our conflict model becomes the final source of truth.
  self.emitter:on("file_open_post", function(_, entry)
    self:attach_result_entry(entry)
  end)
  self.emitter:on("post_layout", function()
    self:_install_click_handlers()
  end)

  self.panel.rev_pretty_name = "Transactional Merge"

  local entries = {}
  local merge_layout = View.get_default_merge_layout()
  for _, path in ipairs(opt.paths) do
    local session_entry = assert(self.merge_session:get(path))
    local function make_stage_file(rev, label)
      local file = File({
        adapter = self.adapter,
        path = path,
        kind = "conflicting",
        rev = rev,
      }) --[[@as vcs.File ]]
      file.winbar = label
      return file
    end

    local result_file = File({
      adapter = self.adapter,
      path = path,
      kind = "conflicting",
      rev = result_rev,
      binary = false,
      get_data = function()
        return vim.deepcopy(session_entry.result)
      end,
      editable = true,
      buffer_context = "[merge-result]",
      on_write = function()
        utils.warn(
          "This is a transactional Result buffer. Use [ Apply Changes ] to write all files."
        )
      end,
    }) --[[@as vcs.File ]]
    result_file.winbar = " RESULT (Not applied)"

    local entry = FileEntry({
      adapter = self.adapter,
      path = path,
      status = "U",
      stats = { conflicts = #session_entry.conflicts },
      kind = "conflicting",
      revs = { a = ours, b = result_rev, c = theirs, d = base },
      layout = merge_layout({
        a = make_stage_file(ours, " CHANGES FROM OURS"),
        b = result_file,
        c = make_stage_file(theirs, " CHANGES FROM THEIRS"),
        d = make_stage_file(base, " COMMON ANCESTOR"),
      }),
    })
    entry.merge_conflicts_remaining = #session_entry.conflicts
    entries[#entries + 1] = entry
  end

  self.files:set_conflicting(entries)
  self.files:update_file_trees()

  self.merge_session.on_change = function()
    self:update_merge_ui()
  end
end

---@override
function MergeView:init_layout()
  StandardView.__get().init_layout(self)
end

---@override
function MergeView:post_open()
  DiffView.__get().post_open(self)
  local first = self.files.conflicting and self.files.conflicting[1]
  if first then
    self:set_file(first)
  end
end

---@override
function MergeView:update_files(opts, callback)
  self.panel:render()
  self.panel:redraw()
  if type(callback) == "function" then
    callback()
  end
end

---@param entry FileEntry
function MergeView:attach_result_entry(entry)
  if entry.kind ~= "conflicting" then
    return
  end
  local main = self.cur_layout and self.cur_layout:get_main_win()
  if not (main and main.file and main.file.bufnr) then
    main = entry.layout and entry.layout:get_main_win()
  end
  if main and main.file and main.file.bufnr then
    self.merge_session:attach(entry.path, main.file.bufnr, entry)
    self:_install_click_handlers()
  end
end

function MergeView:_install_click_handlers()
  router.unregister_owner(self)
  local entry = self.cur_entry
  local current = entry and self.merge_session:get(entry.path)
  if not (current and current.bufnr and api.nvim_buf_is_valid(current.bufnr)) then
    return
  end

  vim.keymap.set("n", "<LeftMouse>", router.callback("mouse", current.bufnr), {
    buffer = current.bufnr,
    silent = true,
    nowait = true,
  })
  for _, conflict in ipairs(current.conflicts) do
    local start_row = self.merge_session:_range(current, conflict)
    local status = conflict.resolved and (" ✔ %s "):format(conflict.choice or "manual")
      or (" Unresolved %d "):format(conflict.id)
    local segments = { { text = status } }
    local indexes = {}
    for _, choice in ipairs({ "ours", "base", "theirs", "all", "manual" }) do
      segments[#segments + 1] = { text = " " }
      indexes[#indexes + 1] = #segments + 1
      local selected = conflict.resolved and conflict.choice == choice
      segments[#segments + 1] = {
        text = selected and ("[ ✔ %s ]"):format(choice:upper())
          or ("[ %s ]"):format(choice:upper()),
      }
    end
    local spans = router.segment_spans(segments)
    for choice_index, segment_index in ipairs(indexes) do
      local choice = ({ "ours", "base", "theirs", "all", "manual" })[choice_index]
      local identity = assert(conflict.identity)
      router.register({
        owner = self,
        handler = function()
          return self:choose_conflict_id(identity, choice)
        end,
        bufnr = current.bufnr,
        line = start_row + 1,
        cursor_line = start_row + 1,
        start_col = spans[segment_index].start_col,
        end_col = spans[segment_index].end_col,
        virtual = true,
      })
    end
  end
end

function MergeView:update_merge_ui()
  router.unregister_owner(self._winbar_routes)
  self._winbar_routes = {}
  local unresolved, total = self.merge_session:counts()
  if self.panel:is_open() and self.panel.winid and api.nvim_win_is_valid(self.panel.winid) then
    local label = self.panel_collapsed and "[ ▶ ]" or "[ ◀ ] Hide files"
    local id = router.register({
      owner = self._winbar_routes,
      handler = function()
        self:toggle_file_panel_width()
      end,
    })
    vim.wo[self.panel.winid].winbar = router.winbar(id, label, "DiffviewFilePanelTitle")
  end
  local entry = self.cur_entry
  local entry_layout = entry and entry.layout --[[@as Diff1|Diff2|Diff3|Diff4|nil]]
  if entry and entry_layout and entry_layout.b then
    local current = assert(self.merge_session:get(entry.path))
    local file_remaining = self.merge_session:entry_remaining(current)
    local file_total = #current.conflicts
    local prev =
      router.register({ owner = self._winbar_routes, action = "navigation.prev_conflict" })
    local next =
      router.register({ owner = self._winbar_routes, action = "navigation.next_conflict" })
    local apply = router.register({ owner = self._winbar_routes, action = "merge.merge_apply" })
    local nav_buttons = router.winbar(prev, "[ ◀ ]") .. " " .. router.winbar(next, "[ ▶ ]")
    local apply_label = unresolved == 0
        and router.winbar(apply, "[ ✔ APPLY CHANGES ]", "DiffviewFilePanelInsertions")
      or router.winbar(apply, "[ APPLY ]")
    local action_buttons = {}
    for _, choice in ipairs({ "ours", "base", "theirs", "all", "manual" }) do
      local route = router.register({
        owner = self._winbar_routes,
        handler = function()
          return self:choose_active_conflict(choice)
        end,
      })
      action_buttons[#action_buttons + 1] = router.winbar(route, ("[ %s ]"):format(choice:upper()))
    end
    for _, choice in ipairs({ "ours", "base", "theirs" }) do
      local route = router.register({
        owner = self._winbar_routes,
        handler = function()
          self:choose_all_conflicts(choice)
          return true
        end,
      })
      action_buttons[#action_buttons + 1] =
        router.winbar(route, ("[ ALL→%s ]"):format(choice:upper()))
    end
    local counts = ("  %%<FILE %d/%d unresolved | ALL %d/%d"):format(
      file_remaining,
      file_total,
      unresolved,
      total
    )
    local stale = self.merge_session.transaction.stale[entry.path]
    local banner = ""
    if stale then
      local refresh = router.register({
        owner = self._winbar_routes,
        handler = function()
          return self:refresh_transaction_status()
        end,
      })
      local reopen = router.register({
        owner = self._winbar_routes,
        handler = function()
          return self:reopen_transaction()
        end,
      })
      local discard = router.register({
        owner = self._winbar_routes,
        handler = function()
          return self:discard_transaction()
        end,
      })
      banner = "  "
        .. router.winbar(refresh, "[ STALE: REFRESH ]", "DiagnosticError")
        .. " "
        .. router.winbar(reopen, "[ REOPEN ]")
        .. " "
        .. router.winbar(discard, "[ DISCARD ]")
    end
    entry_layout.b.file.winbar = "RESULT  "
      .. nav_buttons
      .. "  "
      .. table.concat(action_buttons, " ")
      .. "  "
      .. apply_label
      .. counts
      .. banner
    local current_layout = self.cur_layout --[[@as Diff1|Diff2|Diff3|Diff4|nil]]
    if current_layout and current_layout.b and current_layout.b.file then
      current_layout.b.file.winbar = entry_layout.b.file.winbar
    end
    local winid = current_layout and current_layout.b and current_layout.b.id
    if winid and api.nvim_win_is_valid(winid) then
      vim.wo[winid].winbar = entry_layout.b.file.winbar
    end
  end
  self:_install_click_handlers()
  self.panel:render()
  self.panel:redraw()
end

---@override
function MergeView:close(opts)
  local closed = MergeView.super_class.close(self, opts)
  if closed ~= false then
    router.unregister_owner(self)
    router.unregister_owner(self._winbar_routes)
  end
  return closed
end

function MergeView:_equalize_diff_windows()
  if not self.cur_layout then
    return
  end
  local diff_wins = {}
  local total_w = 0
  for _, sym in ipairs({ "a", "b", "c", "d" }) do
    local win = self.cur_layout[sym]
    if win and win.id and api.nvim_win_is_valid(win.id) then
      table.insert(diff_wins, win.id)
      total_w = total_w + api.nvim_win_get_width(win.id)
    end
  end
  if #diff_wins == 0 or total_w <= 0 then
    return
  end
  local each = math.floor(total_w / #diff_wins)
  for i = 1, #diff_wins - 1 do
    pcall(api.nvim_win_set_width, diff_wins[i], each)
  end
end

function MergeView:toggle_file_panel_width()
  local winid = self.panel.winid
  if not (winid and api.nvim_win_is_valid(winid)) then
    return
  end

  if self.panel_collapsed then
    self.panel_collapsed = false
    api.nvim_win_set_width(winid, self.panel_expanded_width or 35)
    self:_equalize_diff_windows()
  else
    self.panel_expanded_width = api.nvim_win_get_width(winid)
    self.panel_collapsed = true
    api.nvim_win_set_width(winid, 5)
    self:_equalize_diff_windows()
    local current_layout = self.cur_layout --[[@as Diff1|Diff2|Diff3|Diff4|nil]]
    local result_win = current_layout and current_layout.b and current_layout.b.id
    if result_win and api.nvim_win_is_valid(result_win) then
      api.nvim_set_current_win(result_win)
    end
  end
  self:update_merge_ui()
end

---@param choice "ours"|"base"|"theirs"|"all"|"manual"|"none"
---@return boolean
function MergeView:choose_conflict(choice)
  local main = self.cur_layout and self.cur_layout:get_main_win()
  if not (self.cur_entry and main and main.id and api.nvim_win_is_valid(main.id)) then
    return false
  end
  local row = api.nvim_win_get_cursor(main.id)[1]
  local changed = self.merge_session:choose(self.cur_entry.path, row, choice)
  if changed then
    self.cur_layout:sync_scroll()
  end
  return changed
end

---@param identity string
---@param choice "ours"|"base"|"theirs"|"all"|"manual"|"none"
---@return boolean
function MergeView:choose_conflict_id(identity, choice)
  if not self.cur_entry then
    return false
  end
  local current = self.merge_session:get(self.cur_entry.path)
  local conflict = current
    and self.merge_session.transaction:conflict(self.cur_entry.path, identity)
  if not conflict then
    return false
  end
  local changed = self.merge_session:choose(self.cur_entry.path, conflict, choice)
  if changed and self.cur_layout then
    self.cur_layout:sync_scroll()
  end
  return changed
end

---@param choice "ours"|"base"|"theirs"|"all"|"manual"|"none"
---@return boolean
function MergeView:choose_active_conflict(choice)
  if not self.cur_entry then
    return false
  end
  local path = self.cur_entry.path
  local identity = self.merge_session.transaction.active[path]
  if identity then
    return self:choose_conflict_id(identity, choice)
  end
  return self:choose_conflict(choice)
end

---@param choice "ours"|"base"|"theirs"|"all"|"manual"|"none"
function MergeView:choose_all_conflicts(choice)
  if not self.cur_entry then
    return
  end
  self.merge_session:choose_all(self.cur_entry.path, choice)
  self.cur_layout:sync_scroll()
end

---@param choice "ours"|"base"|"theirs"
function MergeView:choose_side(choice)
  if not self.cur_entry then
    return
  end
  self.merge_session:choose_side(self.cur_entry.path, choice)
  self.cur_layout:sync_scroll()
end

---@param delta integer
---@return table?
function MergeView:jump_conflict(delta)
  local main = self.cur_layout and self.cur_layout:get_main_win()
  if not (self.cur_entry and main and main.id and api.nvim_win_is_valid(main.id)) then
    return
  end
  local row = api.nvim_win_get_cursor(main.id)[1]
  local target, index = self.merge_session:jump(self.cur_entry.path, row, delta)
  if target then
    api.nvim_set_current_win(main.id)
    self.cur_layout:sync_scroll()
    api.nvim_win_set_cursor(main.id, { target, 0 })
    pcall(function()
      vim.cmd("normal! zvzz")
    end)
    local current = assert(self.merge_session:get(self.cur_entry.path))
    api.nvim_echo({
      {
        ("Unresolved conflict [%d/%d]"):format(index, self.merge_session:entry_remaining(current)),
      },
    }, false, {})
    pcall(function()
      vim.cmd("redraw")
    end)
    return { current = index, total = self.merge_session:entry_remaining(current) }
  else
    local current = self.merge_session:get(self.cur_entry.path)
    if current and self.merge_session:entry_remaining(current) == 0 then
      api.nvim_echo(
        { { "All conflicts resolved in this file", "DiffviewFilePanelInsertions" } },
        false,
        {}
      )
    end
  end
end

function MergeView:apply_all()
  local ok, err, report = self.merge_session:apply()
  if not ok then
    self:update_merge_ui()
    local rollback = report and report.rollback_failures or {}
    local suffix = #rollback > 0 and (" (%d rollback failure(s))"):format(#rollback) or ""
    utils.err((err or "Unable to apply merge results") .. suffix)
    return false
  end

  self.applied = true
  for _, path in ipairs(self.merge_session.order) do
    local entry = assert(self.merge_session:get(path))
    if entry.bufnr and api.nvim_buf_is_valid(entry.bufnr) then
      vim.bo[entry.bufnr].modified = false
    end
  end
  utils.info("All merge results were applied to the working tree.")
  local tabpage = self.tabpage
  vim.schedule(function()
    require("diffview").close(tabpage, { force = true })
  end)
  return true
end

---@return boolean
function MergeView:refresh_transaction_status()
  local ok, err = self.merge_session:validate()
  self:update_merge_ui()
  if ok then
    utils.info("Merge transaction is current.")
  else
    utils.warn(err or "Merge transaction is stale.")
  end
  return ok
end

---@return boolean
function MergeView:reopen_transaction()
  local fresh = MergeSession(self.adapter, vim.deepcopy(self.merge_session.order))
  self.merge_session = fresh
  fresh.on_change = function()
    self:update_merge_ui()
  end
  for _, file_entry in ipairs(self.files.conflicting or {}) do
    local session_entry = assert(fresh:get(file_entry.path))
    file_entry.merge_conflicts_remaining = #session_entry.conflicts
    local layout = file_entry.layout --[[@as Diff3|Diff4]]
    local result_file = layout.b.file
    result_file.get_data = function()
      return vim.deepcopy(session_entry.result)
    end
    if result_file.bufnr and api.nvim_buf_is_valid(result_file.bufnr) then
      api.nvim_buf_set_lines(result_file.bufnr, 0, -1, false, session_entry.result)
      fresh:attach(file_entry.path, result_file.bufnr, file_entry)
    end
  end
  self:update_merge_ui()
  utils.info("Merge transaction reopened from the current index and working tree.")
  return true
end

---@return boolean
function MergeView:discard_transaction()
  local tabpage = self.tabpage
  vim.schedule(function()
    require("diffview").close(tabpage, { force = true })
  end)
  return true
end

---@override
---@param opts? diffview.View.CloseOpts
---@return boolean
function MergeView:can_close(opts)
  opts = opts or {}
  if self.applied or opts.force then
    return true
  end
  utils.err(
    "Merge results have not been applied. Click [ Apply Changes ] or use :DiffviewClose! to discard them."
  )
  return false
end

M.MergeView = MergeView

return M
