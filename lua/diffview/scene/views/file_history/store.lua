---State owner for FileHistory queries and view mode.

local query = require("diffview.vcs.query")

local M = {}

---@enum FileHistoryQueryStatus
M.QueryStatus = {
  IDLE = "idle",
  STREAMING = "streaming",
  SUCCESS = "success",
  ERROR = "error",
  CANCELLED = "cancelled",
}

---@class FileHistoryViewState
---@field pin_local boolean
---@field pinned_path? string
---@field pinned_files table<string, vcs.File>

---@class FileHistoryStore
---@field entries LogEntry[]
---@field query { status: FileHistoryQueryStatus, received: integer, generation: integer, message?: string, token?: vcs.CancellationToken }
---@field view FileHistoryViewState
---@field private listeners function[]
local FileHistoryStore = {}
FileHistoryStore.__index = FileHistoryStore

---@param opt? { pin_local?: boolean, pinned_path?: string }
---@return FileHistoryStore
function FileHistoryStore.new(opt)
  opt = opt or {}
  return setmetatable({
    entries = {},
    query = { status = M.QueryStatus.IDLE, received = 0, generation = 0 },
    view = {
      pin_local = opt.pin_local == true,
      pinned_path = opt.pinned_path,
      pinned_files = {},
    },
    listeners = {},
  }, FileHistoryStore)
end

---@param listener fun(store: FileHistoryStore, reason: string)
---@return fun()
function FileHistoryStore:subscribe(listener)
  self.listeners[#self.listeners + 1] = listener
  return function()
    for i, candidate in ipairs(self.listeners) do
      if candidate == listener then
        table.remove(self.listeners, i)
        break
      end
    end
  end
end

---@param reason string
function FileHistoryStore:notify(reason)
  for _, listener in ipairs(self.listeners) do
    listener(self, reason)
  end
end

---@return vcs.CancellationToken token
---@return integer generation
function FileHistoryStore:begin_query()
  self:cancel_query("Superseded by a newer history query")
  local token = query.CancellationToken.new()
  local generation = self.query.generation + 1
  self.query = {
    status = M.QueryStatus.STREAMING,
    received = 0,
    generation = generation,
    token = token,
  }
  self:notify("query")
  return token, generation
end

---@param generation integer
---@return boolean
function FileHistoryStore:is_current(generation)
  return self.query.generation == generation
end

---@param entry LogEntry
---@param generation integer
---@return boolean
function FileHistoryStore:append(entry, generation)
  if not self:is_current(generation) or self.query.status ~= M.QueryStatus.STREAMING then
    return false
  end
  self.entries[#self.entries + 1] = entry
  self.query.received = self.query.received + 1
  self:notify("append")
  return true
end

function FileHistoryStore:reset_entries()
  self.entries = {}
  self:notify("reset")
end

---@param generation integer
function FileHistoryStore:complete(generation)
  if not self:is_current(generation) then
    return
  end
  self.query.status = M.QueryStatus.SUCCESS
  self.query.token = nil
  self:notify("query")
end

---@param generation integer
---@param message string
function FileHistoryStore:fail(generation, message)
  if not self:is_current(generation) then
    return
  end
  self.query.status = M.QueryStatus.ERROR
  self.query.message = message
  self.query.token = nil
  self:notify("query")
end

---@param reason? string
---@return boolean
function FileHistoryStore:cancel_query(reason)
  local token = self.query.token
  if self.query.status ~= M.QueryStatus.STREAMING or not token then
    return false
  end
  token:cancel(reason or "History query cancelled")
  self.query.status = M.QueryStatus.CANCELLED
  self.query.message = token:reason()
  self.query.token = nil
  self:notify("query")
  return true
end

M.FileHistoryStore = FileHistoryStore
return M
