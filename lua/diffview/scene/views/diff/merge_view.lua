local lazy = require("diffview.lazy")
local oop = require("diffview.oop")

local Diff3Hor = lazy.access("diffview.scene.layouts.diff_3_hor", "Diff3Hor") ---@type Diff3Hor|LazyModule
local File = lazy.access("diffview.vcs.file", "File") ---@type vcs.File|LazyModule
local FileEntry = lazy.access("diffview.scene.file_entry", "FileEntry") ---@type FileEntry|LazyModule
local MergeSession = lazy.access("diffview.merge_session", "MergeSession") ---@type MergeSession|LazyModule
local NullDiffView = lazy.access("diffview.scene.views.diff.null_diff_view", "NullDiffView") ---@type NullDiffView|LazyModule
local RevType = lazy.access("diffview.vcs.rev", "RevType") ---@type RevType|LazyModule
local StandardView = lazy.access("diffview.scene.views.standard.standard_view", "StandardView") ---@type StandardView|LazyModule
local utils = lazy.require("diffview.utils") ---@module "diffview.utils"

local api = vim.api

local M = {}

---@class MergeView : NullDiffView
---@operator call : MergeView
---@field merge_session MergeSession
---@field applied boolean
---@field panel_collapsed boolean
---@field panel_expanded_width? integer
local MergeView = oop.create_class("MergeView", NullDiffView.__get())

---@param opt { adapter: GitAdapter, paths: string[] }
function MergeView:init(opt)
  local ours = opt.adapter.Rev(RevType.STAGE, 2)
  local theirs = opt.adapter.Rev(RevType.STAGE, 3)
  local base = opt.adapter.Rev(RevType.STAGE, 1)
  local result_rev = opt.adapter.Rev(RevType.CUSTOM)

  self.merge_session = MergeSession(opt.adapter, opt.paths)
  self.applied = false
  self.panel_collapsed = false

  self:super({
    adapter = opt.adapter,
    path_args = opt.paths,
    rev_arg = nil,
    left = ours,
    right = theirs,
    options = {},
  })

  -- Keep the precise DiffText highlight, but remove the broad DiffChange
  -- wash from all three panes. Conflict state is already shown explicitly
  -- by the Result extmarks and their Unresolved labels.
  for _, symbol in ipairs({ "a", "b", "c" }) do
    self.winopts.diff3[symbol].winhl = {
      "DiffAdd:DiffviewDiffAdd",
      "DiffDelete:DiffviewDiffDelete",
      "DiffChange:Normal",
      "DiffText:DiffviewDiffText",
      opt = { method = "prepend" },
    }
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
        utils.warn("This is a transactional Result buffer. Use [ Apply Changes ] to write all files.")
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
      layout = Diff3Hor({
        a = make_stage_file(ours, " CHANGES FROM OURS"),
        b = result_file,
        c = make_stage_file(theirs, " CHANGES FROM THEIRS"),
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

---@param entry FileEntry
function MergeView:attach_result_entry(entry)
  if entry.kind ~= "conflicting" then
    return
  end
  local main = entry.layout:get_main_win()
  if main and main.file and main.file.bufnr then
    self.merge_session:attach(entry.path, main.file.bufnr, entry)
    self:_install_click_handlers()
  end
end

function MergeView:_install_click_handlers()
  local bufs = {}
  if self.panel and self.panel.bufnr and api.nvim_buf_is_valid(self.panel.bufnr) then
    table.insert(bufs, self.panel.bufnr)
  end
  if self.cur_layout then
    for _, sym in ipairs({ "a", "b", "c" }) do
      local win = self.cur_layout[sym]
      if win and win.file and win.file.bufnr and api.nvim_buf_is_valid(win.file.bufnr) then
        table.insert(bufs, win.file.bufnr)
      end
    end
  end

  for _, bufnr in ipairs(bufs) do
    vim.keymap.set("n", "<LeftMouse>", function()
      if self:_handle_left_mouse() then
        return ""
      end
      return "<LeftMouse>"
    end, { buffer = bufnr, expr = true, silent = true, nowait = true })
  end
end

function MergeView:_handle_left_mouse()
  local mouse = vim.fn.getmousepos()
  if mouse.line <= 0 or mouse.column <= 0 or mouse.winid <= 0 then
    return false
  end

  local cur_main = self.cur_layout and self.cur_layout:get_main_win()
  local result_win = cur_main and cur_main.id
  local entry = self.cur_entry

  if result_win and mouse.winid == result_win and entry then
    local current = self.merge_session:get(entry.path)
    if current then
      local conflict_on_line
      for _, c in ipairs(current.conflicts) do
        local s_row = self.merge_session:_range(current, c)
        if s_row + 1 == mouse.line then
          conflict_on_line = c
          break
        end
      end

      if conflict_on_line then
        local sp = vim.fn.screenpos(result_win, mouse.line, 1)
        local is_virt_line = true
        if sp and sp.row > 0 and mouse.screenrow then
          local s_row = self.merge_session:_range(current, conflict_on_line)
          if s_row > 0 then
            is_virt_line = mouse.screenrow < sp.row
          else
            is_virt_line = mouse.screenrow > sp.row
          end
        end

        if is_virt_line then
          local wininfo = vim.fn.getwininfo(result_win)[1]
          local offset = mouse.wincol - (wininfo and wininfo.textoff or 0)

          if offset > 0 then
            local status_str = conflict_on_line.resolved
              and (" ✔ %s "):format(conflict_on_line.choice or "manual")
              or (" Unresolved %d "):format(conflict_on_line.id)
            local prefix_w = vim.fn.strdisplaywidth(status_str)
            local ours_str = conflict_on_line.resolved and conflict_on_line.choice == "ours" and "[ ✔ OURS ]" or "[ OURS ]"
            local ours_w = vim.fn.strdisplaywidth(ours_str)
            local theirs_str = conflict_on_line.resolved and conflict_on_line.choice == "theirs" and "[ ✔ THEIRS ]" or "[ THEIRS ]"
            local theirs_w = vim.fn.strdisplaywidth(theirs_str)

            local ours_start = prefix_w + 1
            local ours_end = ours_start + ours_w
            local theirs_start = ours_end + 1
            local theirs_end = theirs_start + theirs_w

            if offset >= ours_start and offset <= ours_end + 1 then
              self.merge_session:choose(entry.path, conflict_on_line, "ours")
              self.cur_layout:sync_scroll()
              return true
            elseif offset > ours_end + 1 and offset <= theirs_end + 2 then
              self.merge_session:choose(entry.path, conflict_on_line, "theirs")
              self.cur_layout:sync_scroll()
              return true
            else
              return true
            end
          end
        end
      end
    end
  end

  return false
end

function MergeView:update_merge_ui()
  local unresolved, total = self.merge_session:counts()
  if self.panel:is_open() and self.panel.winid and api.nvim_win_is_valid(self.panel.winid) then
    local label = self.panel_collapsed and "[ ▶ ]" or "[ ◀ ] Hide files"
    vim.wo[self.panel.winid].winbar = (
      "%%#DiffviewFilePanelTitle#%%@v:lua.DiffviewMergePanelClick@%s%%X%%*"
    ):format(label)
  end
  local entry = self.cur_entry
  if entry and entry.layout and entry.layout.b then
    local current = assert(self.merge_session:get(entry.path))
    local file_remaining = self.merge_session:entry_remaining(current)
    local file_total = #current.conflicts
    local apply_label = unresolved == 0
      and "%%#DiffviewFilePanelInsertions#%%@v:lua.DiffviewMergeApplyClick@[ ✔ APPLY CHANGES ]%%X%%*"
      or "%%@v:lua.DiffviewMergeApplyClick@[ APPLY ]%%X"
    entry.layout.b.file.winbar = (
      "RESULT  "
      .. apply_label
      .. "  FILE %d/%d unresolved | ALL %d/%d"
    ):format(file_remaining, file_total, unresolved, total)
    local winid = self.cur_layout and self.cur_layout.b and self.cur_layout.b.id
    if winid and api.nvim_win_is_valid(winid) then
      vim.wo[winid].winbar = entry.layout.b.file.winbar
    end
  end
  self.panel:render()
  self.panel:redraw()
end

function MergeView:_equalize_diff_windows()
  if not self.cur_layout then
    return
  end
  local diff_wins = {}
  local total_w = 0
  for _, sym in ipairs({ "a", "b", "c" }) do
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
    local result_win = self.cur_layout and self.cur_layout.b and self.cur_layout.b.id
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

---@param choice "ours"|"base"|"theirs"|"all"|"manual"|"none"
function MergeView:choose_all_conflicts(choice)
  if not self.cur_entry then
    return
  end
  self.merge_session:choose_all(self.cur_entry.path, choice)
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
    api.nvim_win_set_cursor(main.id, { target, 0 })
    self.cur_layout:sync_scroll()
    local current = assert(self.merge_session:get(self.cur_entry.path))
    api.nvim_echo({ {
      ("Unresolved conflict [%d/%d]"):format(index, self.merge_session:entry_remaining(current)),
    } }, false, {})
    return { current = index, total = self.merge_session:entry_remaining(current) }
  end
end

function MergeView:apply_all()
  local ok, err = self.merge_session:apply()
  if not ok then
    utils.err(err or "Unable to apply merge results")
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

---@override
---@param opts? diffview.View.CloseOpts
---@return boolean
function MergeView:can_close(opts)
  opts = opts or {}
  if self.applied or opts.force then
    return true
  end
  utils.err("Merge results have not been applied. Click [ Apply Changes ] or use :DiffviewClose! to discard them.")
  return false
end

_G.DiffviewMergeApplyClick = function()
  local view = require("diffview.lib").get_current_view()
  if view and view.apply_all then
    view:apply_all()
  end
end

_G.DiffviewMergePanelClick = function()
  local view = require("diffview.lib").get_current_view()
  if view and view.merge_session and view.toggle_file_panel_width then
    view:toggle_file_panel_width()
  end
end

_G.DiffviewMergeOursClick = function()
  local view = require("diffview.lib").get_current_view()
  if view and view.choose_conflict then
    view:choose_conflict("ours")
  end
end

_G.DiffviewMergeTheirsClick = function()
  local view = require("diffview.lib").get_current_view()
  if view and view.choose_conflict then
    view:choose_conflict("theirs")
  end
end

M.MergeView = MergeView

return M
