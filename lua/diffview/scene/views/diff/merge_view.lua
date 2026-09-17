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
    self:_install_result_click(main.file.bufnr, main.id, entry.path)
  end
end

function MergeView:_install_result_click(bufnr, winid, path)
  vim.keymap.set("n", "<LeftMouse>", function()
    local mouse = vim.fn.getmousepos()
    if mouse.winid == winid and mouse.line > 0 then
      local current = self.merge_session:get(path)
      if current then
        local conflict = self.merge_session:conflict_at(current, mouse.line, false)
        if conflict and not conflict.resolved then
          local wininfo = vim.fn.getwininfo(winid)[1]
          local line_content = api.nvim_buf_get_lines(bufnr, mouse.line - 1, mouse.line, false)[1] or ""
          local text_end_col = (wininfo and wininfo.textoff or 0)
            + math.max(0, #line_content - (wininfo and wininfo.leftcol or 0))

          if mouse.wincol > text_end_col then
            local offset = mouse.wincol - text_end_col
            local label_len = #(" Unresolved " .. conflict.id .. " ")
            local ours_btn = " [ OURS ]"
            local sep = " "
            local theirs_btn = "[ THEIRS ]"

            if offset > label_len and offset <= label_len + #ours_btn then
              self.merge_session:choose(path, mouse.line, "ours")
              self.cur_layout:sync_scroll()
              return
            elseif offset > label_len + #ours_btn + #sep and offset <= label_len + #ours_btn + #sep + #theirs_btn then
              self.merge_session:choose(path, mouse.line, "theirs")
              self.cur_layout:sync_scroll()
              return
            end
          end
        end
      end
    end

    local m = vim.fn.getmousepos()
    if m.winid > 0 and api.nvim_win_is_valid(m.winid) then
      api.nvim_set_current_win(m.winid)
      pcall(api.nvim_win_set_cursor, m.winid, { m.line, math.max(0, m.column - 1) })
    end
  end, { buffer = bufnr, silent = true, nowait = true })
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

function MergeView:toggle_file_panel_width()
  local winid = self.panel.winid
  if not (winid and api.nvim_win_is_valid(winid)) then
    return
  end

  if self.panel_collapsed then
    self.panel_collapsed = false
    api.nvim_win_set_width(winid, self.panel_expanded_width or 35)
  else
    self.panel_expanded_width = api.nvim_win_get_width(winid)
    self.panel_collapsed = true
    api.nvim_win_set_width(winid, 5)
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
