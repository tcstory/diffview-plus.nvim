---State store for DiffView and its file panel.
---The store owns domain/UI state; views and panels only project it.

local M = {}

---@class DiffStore
---@field files FileDict
---@field reviewed table<string, true>
---@field hide_reviewed boolean
---@field current_entry? FileEntry
---@field filter string
---@field private listeners function[]
local DiffStore = {}
DiffStore.__index = DiffStore

---@param files FileDict
---@return DiffStore
function DiffStore.new(files)
  return setmetatable({
    files = files,
    reviewed = {},
    hide_reviewed = false,
    filter = "",
    listeners = {},
  }, DiffStore)
end

---@param file FileEntry
---@return string
function DiffStore.key(file)
  return file.kind .. ":" .. file.path
end

---@param listener fun(store: DiffStore, reason: string)
---@return fun()
function DiffStore:subscribe(listener)
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
function DiffStore:notify(reason)
  for _, listener in ipairs(self.listeners) do
    listener(self, reason)
  end
end

---@param file FileEntry?
function DiffStore:set_current(file)
  if self.current_entry == file then
    return
  end
  self.current_entry = file
  self:notify("current")
end

---@param file FileEntry
---@return boolean
function DiffStore:is_reviewed(file)
  return self.reviewed[DiffStore.key(file)] == true
end

---@param file FileEntry
---@param reviewed? boolean
function DiffStore:set_reviewed(file, reviewed)
  local key = DiffStore.key(file)
  local next_value = reviewed ~= false
  if (self.reviewed[key] == true) == next_value then
    return
  end
  self.reviewed[key] = next_value and true or nil
  self:notify("reviewed")
end

---@param file FileEntry
function DiffStore:toggle_reviewed(file)
  self:set_reviewed(file, not self:is_reviewed(file))
end

---@return boolean changed
function DiffStore:clear_reviewed()
  if next(self.reviewed) == nil then
    return false
  end
  self.reviewed = {}
  self:notify("reviewed")
  return true
end

---@param keys string[]
function DiffStore:load_reviewed(keys)
  self.reviewed = {}
  for _, key in ipairs(keys) do
    self.reviewed[key] = true
  end
end

---@return boolean changed
function DiffStore:prune_reviewed()
  local valid = {}
  for _, file in self.files:iter() do
    valid[DiffStore.key(file)] = true
  end
  local changed = false
  for key in pairs(self.reviewed) do
    if not valid[key] then
      self.reviewed[key] = nil
      changed = true
    end
  end
  if changed then
    self:notify("reviewed")
  end
  return changed
end

---@param hidden boolean
function DiffStore:set_hide_reviewed(hidden)
  hidden = hidden == true
  if self.hide_reviewed == hidden then
    return
  end
  self.hide_reviewed = hidden
  self:notify("visibility")
end

---@param value string?
function DiffStore:set_filter(value)
  local normalized = vim.trim(value or ""):lower()
  if self.filter == normalized then
    return
  end
  self.filter = normalized
  self:notify("filter")
end

---@param file FileEntry
---@return boolean
function DiffStore:matches_filter(file)
  return self.filter == "" or file.path:lower():find(self.filter, 1, true) ~= nil
end

---@param file FileEntry
---@return boolean
function DiffStore:is_visible(file)
  return self:matches_filter(file) and not (self.hide_reviewed and self:is_reviewed(file))
end

M.DiffStore = DiffStore
return M
