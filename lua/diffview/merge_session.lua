local lazy = require("diffview.lazy")
local oop = require("diffview.oop")

local utils = lazy.require("diffview.utils") ---@module "diffview.utils"
local vcs_utils = lazy.require("diffview.vcs.utils") ---@module "diffview.vcs.utils"

local api = vim.api
local pl = lazy.access(utils, "path") --[[@as PathLib ]]

local M = {}

---@class MergeSession.Conflict
---@field id integer
---@field start_line integer # 1-based start in the initial result.
---@field end_line integer # 1-based inclusive end; may be start_line - 1 for an empty base.
---@field ours string[]
---@field base string[]
---@field theirs string[]
---@field resolved boolean
---@field choice? "ours"|"base"|"theirs"|"manual"
---@field extmark? integer

---@class MergeSession.Entry
---@field path string
---@field absolute_path string
---@field original_bytes? string
---@field existed boolean
---@field mode? integer
---@field endofline boolean
---@field line_ending "\n"|"\r\n"
---@field result string[]
---@field sides table<"ours"|"base"|"theirs", string[]>
---@field conflicts MergeSession.Conflict[]
---@field stage_oids table<integer, string|false>
---@field bufnr? integer
---@field file_entry? FileEntry

---@class MergeSession : diffview.Object
---@operator call : MergeSession
---@field adapter GitAdapter
---@field entries table<string, MergeSession.Entry>
---@field order string[]
---@field namespace integer
---@field on_change? fun(session: MergeSession, entry: MergeSession.Entry)
local MergeSession = oop.create_class("MergeSession")

local function copy_lines(lines)
  return vim.deepcopy(lines or {})
end

---@param bytes string
---@return string[]
local function bytes_to_lines(bytes)
  if bytes == "" then
    return {}
  end
  local normalized = bytes:gsub("\r\n", "\n")
  local lines = vim.split(normalized, "\n", { plain = true })
  if normalized:sub(-1) == "\n" then
    table.remove(lines)
  end
  return lines
end

---@param path string
---@return boolean
local function read_file_snapshot(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return nil, nil
  end
  local fd = vim.uv.fs_open(path, "r", 0)
  if not fd then
    return nil, stat
  end
  local bytes = stat.size > 0 and vim.uv.fs_read(fd, stat.size, 0) or ""
  vim.uv.fs_close(fd)
  return bytes, stat
end

---@param path string
---@param bytes string
---@param mode? integer
---@return boolean ok
---@return string? err
local function write_bytes(path, bytes, mode)
  local fd, open_err = vim.uv.fs_open(path, "w", mode or 420)
  if not fd then
    return false, open_err
  end
  local written, write_err = vim.uv.fs_write(fd, bytes, 0)
  local _, close_err = vim.uv.fs_close(fd)
  if written ~= #bytes then
    return false, write_err or "short write"
  end
  if close_err then
    return false, close_err
  end
  return true
end

---@param adapter GitAdapter
---@param path string
---@param stage integer
---@return string[]?
local function read_stage(adapter, path, stage)
  local out, code = adapter:exec_sync({ "show", (":%d:%s"):format(stage, path) }, {
    cwd = adapter.ctx.toplevel,
    silent = true,
  })
  return code == 0 and out or nil
end

---@param adapter GitAdapter
---@param path string
---@param stage integer
---@return string|false
local function read_stage_oid(adapter, path, stage)
  local out, code = adapter:exec_sync({ "rev-parse", "--verify", (":%d:%s"):format(stage, path) }, {
    cwd = adapter.ctx.toplevel,
    silent = true,
  })
  return code == 0 and out[1] or false
end

---@param adapter GitAdapter
---@param path string
---@return string[]? merged
---@return integer? conflict_count
---@return table<"ours"|"base"|"theirs", string[]>? sides
---@return string? err
local function diff3_merge(adapter, path)
  local temp_dir = vim.fn.tempname()
  if vim.fn.mkdir(temp_dir, "p") ~= 1 then
    return nil, nil, nil, "Unable to create a temporary merge directory"
  end

  local paths = {
    ours = pl:join(temp_dir, "ours"),
    base = pl:join(temp_dir, "base"),
    theirs = pl:join(temp_dir, "theirs"),
  }

  local sides = {
    ours = read_stage(adapter, path, 2) or {},
    base = read_stage(adapter, path, 1) or {},
    theirs = read_stage(adapter, path, 3) or {},
  }
  local has_base = read_stage_oid(adapter, path, 1) ~= false

  vim.fn.writefile(sides.ours, paths.ours, "b")
  vim.fn.writefile(sides.base, paths.base, "b")
  vim.fn.writefile(sides.theirs, paths.theirs, "b")

  local cmd = { "merge-file", "-p" }
  if has_base then
    vim.list_extend(cmd, { "--diff3", "-L", "OURS", "-L", "BASE", "-L", "THEIRS" })
  else
    vim.list_extend(cmd, { "-L", "OURS", "-L", "", "-L", "THEIRS" })
  end
  vim.list_extend(cmd, { paths.ours, paths.base, paths.theirs })

  local out, code, stderr = adapter:exec_sync(cmd, {
    cwd = adapter.ctx.toplevel,
    silent = true,
  })

  vim.fn.delete(temp_dir, "rf")

  -- `git merge-file --stdout` returns the conflict count, capped at 127.
  if not code or code > 127 then
    return nil, nil, nil, table.concat(stderr or { "git merge-file failed" }, "\n")
  end
  return out, code, sides
end

---@param merged string[]
---@param fallbacks? MergeSession.Conflict[]
---@return string[] result
---@return MergeSession.Conflict[] conflicts
local function clean_result(merged, fallbacks)
  local parsed = vcs_utils.parse_conflicts(merged)
  local result = {}
  local conflicts = {}
  local cursor = 1

  for index, region in ipairs(parsed) do
    for line = cursor, region.first - 1 do
      result[#result + 1] = merged[line]
    end

    local base = copy_lines(region.base.content)
    if #base == 0 and fallbacks then
      for _, fallback in ipairs(fallbacks) do
        if
          vim.deep_equal(fallback.ours, region.ours.content)
          and vim.deep_equal(fallback.theirs, region.theirs.content)
        then
          base = copy_lines(fallback.base)
          break
        end
      end
    end
    local start_line = #result + 1
    vim.list_extend(result, base)
    conflicts[#conflicts + 1] = {
      id = index,
      start_line = start_line,
      end_line = start_line + #base - 1,
      ours = copy_lines(region.ours.content),
      base = base,
      theirs = copy_lines(region.theirs.content),
      resolved = false,
    }
    cursor = region.last + 1
  end

  for line = cursor, #merged do
    result[#result + 1] = merged[line]
  end

  return result, conflicts
end

---@param adapter GitAdapter
---@param paths string[]
function MergeSession:init(adapter, paths)
  self.adapter = adapter
  self.entries = {}
  self.order = {}
  self.namespace = api.nvim_create_namespace("diffview_transactional_merge")

  for _, path in ipairs(paths) do
    local merged, conflict_count, sides, err = diff3_merge(adapter, path)
    if not merged then
      error(("Failed to prepare merge result for '%s': %s"):format(path, err or "unknown error"))
    end
    local absolute_path = pl:absolute(path, adapter.ctx.toplevel)
    local original_bytes, stat = read_file_snapshot(absolute_path)
    -- The worktree can already contain partial manual resolutions. Use it as
    -- the source of truth when present, while still caching the three index
    -- stages for whole-side choices and stale-index validation.
    local generated_result, generated_conflicts = clean_result(merged)
    local result, conflicts
    if original_bytes ~= nil then
      result, conflicts = clean_result(bytes_to_lines(original_bytes), generated_conflicts)
    else
      result, conflicts = generated_result, generated_conflicts
    end
    if original_bytes == nil and conflict_count > 0 and #conflicts == 0 then
      error(("Failed to identify the unresolved regions in '%s'"):format(path))
    end
    local entry = {
      path = path,
      absolute_path = absolute_path,
      original_bytes = original_bytes,
      existed = stat ~= nil,
      mode = stat and stat.mode or nil,
      endofline = original_bytes ~= nil and original_bytes:sub(-1) == "\n",
      line_ending = original_bytes and original_bytes:find("\r\n", 1, true) and "\r\n" or "\n",
      result = result,
      sides = assert(sides),
      conflicts = conflicts,
      stage_oids = {
        [1] = read_stage_oid(adapter, path, 1),
        [2] = read_stage_oid(adapter, path, 2),
        [3] = read_stage_oid(adapter, path, 3),
      },
    }
    self.entries[path] = entry
    self.order[#self.order + 1] = path
  end
end

---@param path string
---@return MergeSession.Entry?
function MergeSession:get(path)
  return self.entries[path]
end

---@param entry MergeSession.Entry
---@return integer unresolved
function MergeSession:entry_remaining(entry)
  local count = 0
  for _, conflict in ipairs(entry.conflicts) do
    if not conflict.resolved then
      count = count + 1
    end
  end
  return count
end

---@return integer unresolved
---@return integer total
function MergeSession:counts()
  local unresolved, total = 0, 0
  for _, path in ipairs(self.order) do
    local entry = self.entries[path]
    total = total + #entry.conflicts
    unresolved = unresolved + self:entry_remaining(entry)
  end
  return unresolved, total
end

---@param entry MergeSession.Entry
---@param conflict MergeSession.Conflict
---@return integer start_row # 0-based, inclusive
---@return integer end_row # 0-based, exclusive
function MergeSession:_range(entry, conflict)
  if entry.bufnr and conflict.extmark and api.nvim_buf_is_valid(entry.bufnr) then
    local mark = api.nvim_buf_get_extmark_by_id(
      entry.bufnr,
      self.namespace,
      conflict.extmark,
      { details = true }
    )
    if mark and #mark > 0 then
      return mark[1], mark[3].end_row or mark[1]
    end
  end
  return conflict.start_line - 1, conflict.end_line
end

---@param entry MergeSession.Entry
---@param conflict MergeSession.Conflict
function MergeSession:_place_mark(entry, conflict)
  if not (entry.bufnr and api.nvim_buf_is_valid(entry.bufnr)) then
    return
  end
  local start_row, end_row = self:_range(entry, conflict)
  if conflict.extmark then
    pcall(api.nvim_buf_del_extmark, entry.bufnr, self.namespace, conflict.extmark)
  end
  local virt_line
  if conflict.resolved then
    virt_line = {
      { (" ✔ %s "):format(conflict.choice or "manual"), "DiffviewFilePanelInsertions" },
      { " ", "Normal" },
      { conflict.choice == "ours" and "[ ✔ OURS ]" or "[ OURS ]", "DiffviewFilePanelInsertions" },
      { " ", "Normal" },
      { conflict.choice == "theirs" and "[ ✔ THEIRS ]" or "[ THEIRS ]", "DiffviewFilePanelDeletions" },
    }
  else
    virt_line = {
      { (" Unresolved %d "):format(conflict.id), "DiagnosticError" },
      { " ", "Normal" },
      { "[ OURS ]", "DiffviewFilePanelInsertions" },
      { " ", "Normal" },
      { "[ THEIRS ]", "DiffviewFilePanelDeletions" },
    }
  end
  conflict.extmark = api.nvim_buf_set_extmark(entry.bufnr, self.namespace, start_row, 0, {
    end_row = end_row,
    end_col = 0,
    virt_lines = { virt_line },
    virt_lines_above = true,
    right_gravity = false,
    end_right_gravity = true,
  })
end

---@param path string
---@param bufnr integer
---@param file_entry FileEntry
function MergeSession:attach(path, bufnr, file_entry)
  local entry = assert(self.entries[path])
  entry.bufnr = bufnr
  entry.file_entry = file_entry
  api.nvim_buf_clear_namespace(bufnr, self.namespace, 0, -1)
  for _, conflict in ipairs(entry.conflicts) do
    self:_place_mark(entry, conflict)
  end
  self:_changed(entry)
end

---@param entry MergeSession.Entry
function MergeSession:_changed(entry)
  if entry.file_entry then
    entry.file_entry.merge_conflicts_remaining = self:entry_remaining(entry)
  end
  if self._update_depth and self._update_depth > 0 then
    self._pending_changes = self._pending_changes or {}
    self._pending_changes[entry] = true
  elseif self.on_change then
    self.on_change(self, entry)
  end
end

function MergeSession:_begin_update()
  self._update_depth = (self._update_depth or 0) + 1
end

function MergeSession:_end_update()
  self._update_depth = math.max((self._update_depth or 1) - 1, 0)
  if self._update_depth > 0 then
    return
  end
  local pending = self._pending_changes or {}
  self._pending_changes = nil
  if self.on_change then
    for entry in pairs(pending) do
      self.on_change(self, entry)
    end
  end
end

---@param entry MergeSession.Entry
---@param row integer # 1-based cursor row
---@param unresolved_only? boolean
---@return MergeSession.Conflict?
function MergeSession:conflict_at(entry, row, unresolved_only)
  local next_conflict
  for _, conflict in ipairs(entry.conflicts) do
    if not unresolved_only or not conflict.resolved then
      local start_row, end_row = self:_range(entry, conflict)
      if row - 1 >= start_row and row - 1 <= math.max(start_row, end_row - 1) then
        return conflict
      end
      if not next_conflict and start_row >= row - 1 then
        next_conflict = conflict
      end
    end
  end
  if next_conflict then
    return next_conflict
  end
  for _, conflict in ipairs(entry.conflicts) do
    if not unresolved_only or not conflict.resolved then
      return conflict
    end
  end
end

---@param path string
---@param row_or_conflict integer|MergeSession.Conflict
---@param choice "ours"|"base"|"theirs"|"all"|"manual"|"none"
---@return boolean changed
function MergeSession:choose(path, row_or_conflict, choice)
  local entry = assert(self.entries[path])
  local conflict
  if type(row_or_conflict) == "table" then
    conflict = row_or_conflict
  else
    local row = row_or_conflict
    -- A resolved region remains selectable so the user can revise an earlier
    -- choice. Outside any tracked region, fall forward to the next unresolved
    -- one (wrapping at the end), which matches the navigation actions.
    for _, candidate in ipairs(entry.conflicts) do
      local start_row, end_row = self:_range(entry, candidate)
      if row - 1 >= start_row and row - 1 <= math.max(start_row, end_row - 1) then
        conflict = candidate
        break
      end
    end
    conflict = conflict or self:conflict_at(entry, row, true)
  end
  if not conflict then
    return false
  end

  local content
  if choice == "manual" then
    content = nil
  elseif choice == "none" then
    content = {}
  elseif choice == "all" then
    content = utils.vec_join(conflict.ours, conflict.base, conflict.theirs)
  else
    content = conflict[choice]
  end

  if content then
    local start_row, end_row = self:_range(entry, conflict)
    api.nvim_buf_set_lines(assert(entry.bufnr), start_row, end_row, false, content)
    conflict.start_line = start_row + 1
    conflict.end_line = start_row + #content
  end

  conflict.resolved = true
  conflict.choice = choice == "none" and "manual" or choice
  self:_place_mark(entry, conflict)
  self:_changed(entry)
  return true
end

---@param path string
---@param choice "ours"|"base"|"theirs"|"all"|"manual"|"none"
function MergeSession:choose_all(path, choice)
  local entry = assert(self.entries[path])
  self:_begin_update()
  local ok, err = pcall(function()
    for _, conflict in ipairs(entry.conflicts) do
      if not conflict.resolved then
        local start_row = self:_range(entry, conflict)
        self:choose(path, start_row + 1, choice)
      end
    end
  end)
  self:_end_update()
  if not ok then
    error(err)
  end
end

---@param path string
---@param choice "ours"|"base"|"theirs"
function MergeSession:choose_side(path, choice)
  local entry = assert(self.entries[path])
  local content = copy_lines(assert(entry.sides[choice]))
  entry.result = content

  if entry.bufnr and api.nvim_buf_is_valid(entry.bufnr) then
    api.nvim_buf_clear_namespace(entry.bufnr, self.namespace, 0, -1)
    api.nvim_buf_set_lines(entry.bufnr, 0, -1, false, content)
  end

  for _, conflict in ipairs(entry.conflicts) do
    conflict.resolved = true
    conflict.choice = choice
    conflict.extmark = nil
  end
  self:_changed(entry)
end

---@param path string
---@param row integer
---@param delta integer
---@return integer? target_row # 1-based
---@return integer? index
function MergeSession:jump(path, row, delta)
  local entry = assert(self.entries[path])
  local pending = {}
  for _, conflict in ipairs(entry.conflicts) do
    if not conflict.resolved then
      pending[#pending + 1] = conflict
    end
  end
  if #pending == 0 then
    return
  end

  local target = delta > 0 and 1 or #pending
  local cursor_row = row - 1
  for index, conflict in ipairs(pending) do
    local start_row, end_row = self:_range(entry, conflict)
    if cursor_row >= start_row and cursor_row <= math.max(start_row, end_row - 1) then
      target = (index + (delta > 0 and 1 or -1) - 1) % #pending + 1
      break
    elseif delta > 0 and start_row > cursor_row then
      target = index
      break
    elseif delta < 0 and start_row < cursor_row then
      target = index
    end
  end
  local start_row = self:_range(entry, pending[target])
  return start_row + 1, target
end

---@return boolean ok
---@return string? err
function MergeSession:apply()
  local unresolved = self:counts()
  if unresolved > 0 then
    return false, ("%d conflict(s) are still unresolved"):format(unresolved)
  end

  for _, path in ipairs(self.order) do
    local entry = self.entries[path]
    for stage = 1, 3 do
      if read_stage_oid(self.adapter, path, stage) ~= entry.stage_oids[stage] then
        return false, ("Git index changed outside the merge session: %s (stage %d)"):format(path, stage)
      end
    end
    local current_bytes, stat = read_file_snapshot(entry.absolute_path)
    if (stat ~= nil) ~= entry.existed or current_bytes ~= entry.original_bytes then
      return false, ("Working-tree file changed outside the merge session: %s"):format(path)
    end
  end

  local prepared = {}
  for _, path in ipairs(self.order) do
    local entry = self.entries[path]
    local lines = entry.bufnr and api.nvim_buf_is_valid(entry.bufnr)
        and api.nvim_buf_get_lines(entry.bufnr, 0, -1, false)
      or entry.result
    local bytes = table.concat(lines, "\n")
    if entry.endofline then
      bytes = bytes .. "\n"
    end
    if entry.line_ending == "\r\n" then
      bytes = bytes:gsub("\n", "\r\n")
    end
    local temp_path = entry.absolute_path .. (".diffview-result-%d"):format(vim.uv.hrtime())
    local ok, err = write_bytes(temp_path, bytes, entry.mode)
    if not ok then
      for _, item in ipairs(prepared) do
        vim.fn.delete(item.temp)
      end
      return false, ("Could not prepare result for '%s': %s"):format(path, err or "")
    end
    prepared[#prepared + 1] = { entry = entry, temp = temp_path, bytes = bytes }
  end

  local applied = {}
  for _, item in ipairs(prepared) do
    local ok, err = vim.uv.fs_rename(item.temp, item.entry.absolute_path)
    if not ok then
      for _, rollback in ipairs(applied) do
        if rollback.entry.existed then
          write_bytes(rollback.entry.absolute_path, rollback.entry.original_bytes or "", rollback.entry.mode)
        else
          vim.fn.delete(rollback.entry.absolute_path)
        end
      end
      for _, pending in ipairs(prepared) do
        vim.fn.delete(pending.temp)
      end
      return false, ("Could not apply result for '%s': %s"):format(item.entry.path, err or "")
    end
    applied[#applied + 1] = item
  end

  return true
end

M.MergeSession = MergeSession
M.clean_result = clean_result

return M
