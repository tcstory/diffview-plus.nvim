local lazy = require("diffview.lazy")
local MergeProjection = require("diffview.scene.views.diff.merge_projection").MergeProjection
local MergeTransaction = require("diffview.domain.merge_transaction").MergeTransaction

local utils = lazy.require("diffview.utils") ---@module "diffview.utils"
local vcs_utils = lazy.require("diffview.vcs.utils") ---@module "diffview.vcs.utils"

local api = vim.api
local pl = lazy.access(utils, "path") --[[@as PathLib ]]

local M = {}

---@class MergeSession.Conflict
---@field id integer
---@field identity? string # Stable transaction identity; independent of buffer rows.
---@field start_line integer # 1-based start in the initial result.
---@field end_line integer # 1-based inclusive end; may be start_line - 1 for an empty base.
---@field ours string[]
---@field base string[]
---@field theirs string[]
---@field resolved boolean
---@field choice? "ours"|"base"|"theirs"|"all"|"manual"
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

---@class MergeSession
---@operator call : MergeSession
---@field adapter GitAdapter
---@field entries table<string, MergeSession.Entry>
---@field order string[]
---@field namespace integer
---@field projection MergeProjection
---@field transaction MergeTransaction
---@field on_change? fun(session: MergeSession, entry: MergeSession.Entry)
local MergeSession = {}
MergeSession.__index = MergeSession
setmetatable(MergeSession, {
  __call = function(_, ...)
    local session = setmetatable({}, MergeSession)
    session:init(...)
    return session
  end,
})

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
---@return string? bytes
---@return uv.aliases.fs_stat_table? stat
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

---@param path string
---@return uv.aliases.fs_stat_table?
local function lstat(path)
  return vim.uv.fs_lstat(path)
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
  self.projection = MergeProjection.new()
  self.namespace = self.projection.namespace

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
  self.transaction = MergeTransaction.new(self.entries, self.order)
end

---@param path string
---@return MergeSession.Entry?
function MergeSession:get(path)
  return self.entries[path]
end

---@param entry MergeSession.Entry
---@return integer unresolved
function MergeSession:entry_remaining(entry)
  return self.transaction:entry_remaining(entry)
end

---@return integer unresolved
---@return integer total
function MergeSession:counts()
  return self.transaction:counts()
end

---@param entry MergeSession.Entry
---@param conflict MergeSession.Conflict
---@return integer start_row # 0-based, inclusive
---@return integer end_row # 0-based, exclusive
function MergeSession:_range(entry, conflict)
  return self.projection:range(entry.path, conflict)
end

---@param entry MergeSession.Entry
---@param conflict MergeSession.Conflict
function MergeSession:_place_mark(entry, conflict)
  self.projection:place(entry.path, conflict)
end

---@param path string
---@param bufnr integer
---@param file_entry FileEntry
function MergeSession:attach(path, bufnr, file_entry)
  local entry = assert(self.entries[path])
  entry.bufnr = bufnr
  entry.file_entry = file_entry
  self.projection:attach(path, bufnr)
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
    ---@cast row_or_conflict MergeSession.Conflict
    conflict = row_or_conflict
  else
    ---@cast row_or_conflict integer
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
  self.transaction:set_active(path, conflict.identity)

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

  self.transaction:choose(path, assert(conflict.identity), choice)
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
    self.projection:clear(path)
    api.nvim_buf_set_lines(entry.bufnr, 0, -1, false, content)
  end

  for _, conflict in ipairs(entry.conflicts) do
    conflict.resolved = true
    conflict.choice = choice
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
  if not self.transaction.active[path] then
    local current = self:conflict_at(entry, row, true)
    if current then
      self.transaction:set_active(path, current.identity)
      -- Preserve the old first-navigation behaviour: navigation from inside
      -- a conflict moves past that conflict rather than selecting it again.
      local start_row, end_row = self:_range(entry, current)
      if row - 1 < start_row or row - 1 > math.max(start_row, end_row - 1) then
        self.transaction:set_active(path, nil)
      end
    end
  end
  local conflict, index = self.transaction:navigate(path, delta, true)
  if not conflict then
    return
  end
  local start_row = self:_range(entry, conflict)
  return start_row + 1, index
end

---@return boolean ok
---@return string? err
function MergeSession:validate()
  self.transaction:set_report("validating", "running")
  self.transaction:clear_stale()
  for _, path in ipairs(self.order) do
    local entry = self.entries[path]
    local target = lstat(entry.absolute_path)
    if target and target.type == "link" then
      local message = ("Refusing to replace symlink: %s"):format(path)
      self.transaction:mark_stale(path, "worktree", message)
      self.transaction:set_report("failed", "stale", message)
      return false, message
    end
    for stage = 1, 3 do
      if read_stage_oid(self.adapter, path, stage) ~= entry.stage_oids[stage] then
        local message = ("Git index changed outside the merge session: %s (stage %d)"):format(
          path,
          stage
        )
        self.transaction:mark_stale(path, "index", message)
        self.transaction:set_report("failed", "stale", message)
        return false, message
      end
    end
    local current_bytes, stat = read_file_snapshot(entry.absolute_path)
    if (stat ~= nil) ~= entry.existed or current_bytes ~= entry.original_bytes then
      local message = ("Working-tree file changed outside the merge session: %s"):format(path)
      self.transaction:mark_stale(path, "worktree", message)
      self.transaction:set_report("failed", "stale", message)
      return false, message
    end
  end
  self.transaction:set_report("validating", "ok")
  return true
end

---@return boolean ok
---@return string? err
---@return table report
function MergeSession:apply()
  local unresolved = self:counts()
  if unresolved > 0 then
    local message = ("%d conflict(s) are still unresolved"):format(unresolved)
    self.transaction:set_report("failed", "unresolved", message)
    return false, message, self.transaction.report
  end

  local valid, validation_err = self:validate()
  if not valid then
    return false, validation_err, self.transaction.report
  end

  self.transaction:set_report("preparing", "running")
  self.transaction.report.files = {}
  self.transaction.report.rollback_failures = {}
  self.transaction.report.atomicity =
    "All results are prepared first; each path is atomically renamed; cross-file rollback is best effort."
  self.transaction.report.metadata = {
    permissions = "preserved",
    symlinks = "rejected",
    acl_xattr = "best-effort (platform APIs do not provide a portable guarantee)",
  }
  local prepared = {}
  for _, path in ipairs(self.order) do
    local entry = self.entries[path]
    local lines = entry.bufnr
        and api.nvim_buf_is_valid(entry.bufnr)
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
      local message = ("Could not prepare result for '%s': %s"):format(path, err or "")
      self.transaction:set_report("failed", "prepare_failed", message)
      return false, message, self.transaction.report
    end
    if entry.mode then
      local chmod_ok, chmod_err = vim.uv.fs_chmod(temp_path, entry.mode)
      if not chmod_ok then
        vim.fn.delete(temp_path)
        for _, item in ipairs(prepared) do
          vim.fn.delete(item.temp)
        end
        local message = ("Could not preserve permissions for '%s': %s"):format(
          path,
          chmod_err or ""
        )
        self.transaction:set_report("failed", "prepare_failed", message)
        return false, message, self.transaction.report
      end
    end
    local item = {
      entry = entry,
      temp = temp_path,
      backup = entry.absolute_path .. (".diffview-backup-%d"):format(vim.uv.hrtime()),
      bytes = bytes,
    }
    prepared[#prepared + 1] = item
    self.transaction.report.files[path] = { status = "prepared" }
  end

  self.transaction:set_report("writing", "running")
  local applied = {}
  local function rollback_applied()
    for index = #applied, 1, -1 do
      local rollback = applied[index]
      vim.fn.delete(rollback.entry.absolute_path)
      if rollback.entry.existed then
        local restored, restore_err =
          vim.uv.fs_rename(rollback.backup, rollback.entry.absolute_path)
        if not restored then
          self.transaction.report.rollback_failures[#self.transaction.report.rollback_failures + 1] =
            {
              path = rollback.entry.path,
              error = restore_err,
            }
        end
      end
    end
  end
  for _, item in ipairs(prepared) do
    if item.entry.existed then
      local backup_ok, backup_err = vim.uv.fs_rename(item.entry.absolute_path, item.backup)
      if not backup_ok then
        rollback_applied()
        for _, pending in ipairs(prepared) do
          vim.fn.delete(pending.temp)
        end
        local message = ("Could not create rollback backup for '%s': %s"):format(
          item.entry.path,
          backup_err or ""
        )
        self.transaction.report.files[item.entry.path].status = "backup_failed"
        self.transaction:set_report("failed", "write_failed", message)
        return false, message, self.transaction.report
      end
    end
    local ok, err = vim.uv.fs_rename(item.temp, item.entry.absolute_path)
    if not ok then
      if item.entry.existed then
        local restored, restore_err = vim.uv.fs_rename(item.backup, item.entry.absolute_path)
        if not restored then
          self.transaction.report.rollback_failures[#self.transaction.report.rollback_failures + 1] =
            {
              path = item.entry.path,
              error = restore_err,
            }
        end
      end
      rollback_applied()
      for _, pending in ipairs(prepared) do
        vim.fn.delete(pending.temp)
      end
      local message = ("Could not apply result for '%s': %s"):format(item.entry.path, err or "")
      if #self.transaction.report.rollback_failures > 0 then
        message = message
          .. ("; rollback failed for %d file(s)"):format(#self.transaction.report.rollback_failures)
      end
      self.transaction.report.files[item.entry.path].status = "write_failed"
      self.transaction:set_report("failed", "write_failed", message)
      return false, message, self.transaction.report
    end
    applied[#applied + 1] = item
    self.transaction.report.files[item.entry.path].status = "applied"
  end

  for _, item in ipairs(applied) do
    if item.entry.existed then
      vim.fn.delete(item.backup)
    end
  end
  self.transaction:set_report("applied", "ok")
  return true, nil, self.transaction.report
end

M.MergeSession = MergeSession
M.clean_result = clean_result

return M
