local M = {}

---@alias MergeChoice "ours"|"base"|"theirs"|"all"|"manual"|"none"

---@class MergeTransaction
---@field entries table<string, MergeSession.Entry>
---@field order string[]
---@field state "editing"|"preparing"|"validating"|"writing"|"applied"|"failed"
---@field active table<string, string>
---@field stale table<string, { source: "index"|"worktree", message: string }>
---@field report table
local MergeTransaction = {}
MergeTransaction.__index = MergeTransaction

---@param entries table<string, MergeSession.Entry>
---@param order string[]
---@return MergeTransaction
function MergeTransaction.new(entries, order)
  local self = setmetatable({
    entries = entries,
    order = order,
    state = "editing",
    active = {},
    stale = {},
    report = { phase = "editing", status = "pending", files = {}, rollback_failures = {} },
  }, MergeTransaction)
  for _, path in ipairs(order) do
    local entry = entries[path]
    for index, conflict in ipairs(entry.conflicts) do
      conflict.identity = conflict.identity or (path .. "#" .. index)
    end
  end
  return self
end

---@param path string
---@param identity string
---@return MergeSession.Conflict?
function MergeTransaction:conflict(path, identity)
  local entry = self.entries[path]
  if not entry then
    return nil
  end
  for _, conflict in ipairs(entry.conflicts) do
    if conflict.identity == identity then
      return conflict
    end
  end
end

---@param entry MergeSession.Entry
---@return integer
function MergeTransaction:entry_remaining(entry)
  local count = 0
  for _, conflict in ipairs(entry.conflicts) do
    if not conflict.resolved then
      count = count + 1
    end
  end
  return count
end

---@return integer, integer
function MergeTransaction:counts()
  local unresolved, total = 0, 0
  for _, path in ipairs(self.order) do
    local entry = self.entries[path]
    unresolved = unresolved + self:entry_remaining(entry)
    total = total + #entry.conflicts
  end
  return unresolved, total
end

---@param path string
---@param identity string
---@param choice MergeChoice
---@return MergeSession.Conflict?
function MergeTransaction:choose(path, identity, choice)
  local conflict = self:conflict(path, identity)
  if not conflict then
    return nil
  end
  conflict.resolved = true
  local selected = choice == "none" and "manual" or choice
  conflict.choice = selected --[[@as "ours"|"base"|"theirs"|"all"|"manual"]]
  self.active[path] = identity
  self.state = "editing"
  return conflict
end

---@param path string
---@param identity? string
function MergeTransaction:set_active(path, identity)
  if identity and self:conflict(path, identity) then
    self.active[path] = identity
  else
    self.active[path] = nil
  end
end

---@param path string
---@param delta integer
---@param unresolved_only? boolean
---@return MergeSession.Conflict?, integer?, integer?
function MergeTransaction:navigate(path, delta, unresolved_only)
  local entry = self.entries[path]
  if not entry then
    return nil
  end
  local candidates = {}
  for _, conflict in ipairs(entry.conflicts) do
    if not unresolved_only or not conflict.resolved then
      candidates[#candidates + 1] = conflict
    end
  end
  if #candidates == 0 then
    return nil
  end

  local current = self.active[path]
  local target = delta > 0 and 1 or #candidates
  for index, conflict in ipairs(candidates) do
    if conflict.identity == current then
      target = (index + (delta > 0 and 1 or -1) - 1) % #candidates + 1
      break
    end
  end
  local conflict = candidates[target]
  self.active[path] = conflict.identity
  return conflict, target, #candidates
end

---@param path string
---@param source "index"|"worktree"
---@param message string
function MergeTransaction:mark_stale(path, source, message)
  self.stale[path] = { source = source, message = message }
end

---@param path? string
function MergeTransaction:clear_stale(path)
  if path then
    self.stale[path] = nil
  else
    self.stale = {}
  end
end

---@param phase "editing"|"preparing"|"validating"|"writing"|"applied"|"failed"
---@param status string
---@param message? string
function MergeTransaction:set_report(phase, status, message)
  self.state = phase
  self.report.phase = phase
  self.report.status = status
  self.report.message = message
end

M.MergeTransaction = MergeTransaction

return M
