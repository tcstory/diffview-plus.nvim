---Structured lifecycle ownership for cancellable view effects.
---
---A scope owns resources and child scopes. Closing it is idempotent, marks the
---scope cancelled before callbacks run, and disposes children/resources in
---reverse registration order. This module is intentionally plain Lua: it has
---no dependency on the legacy OOP or coroutine helpers.

---@class diffview.EffectScope.Entry
---@field value any
---@field cleanup? fun(value: any, reason?: string)
---@field active boolean

---@class diffview.EffectScope
---@field state "active"|"closing"|"closed"
---@field reason? string
---@field parent? diffview.EffectScope
---@field private entries diffview.EffectScope.Entry[]
---@field private children diffview.EffectScope[]
---@field private listeners (fun(scope: diffview.EffectScope, reason?: string))[]
local EffectScope = {}
EffectScope.__index = EffectScope

---@param parent? diffview.EffectScope
---@return diffview.EffectScope
function EffectScope.new(parent)
  local scope = setmetatable({
    state = "active",
    parent = parent,
    entries = {},
    children = {},
    listeners = {},
  }, EffectScope)
  if parent then
    if parent:check() then
      scope:close(parent.reason)
    else
      parent.children[#parent.children + 1] = scope
    end
  end
  return scope
end

---@return boolean cancelled
function EffectScope:check()
  return self.state ~= "active"
end

---@return diffview.EffectScope
function EffectScope:child()
  return EffectScope.new(self)
end

---@param value any Resource, disposer function, or opaque value with explicit cleanup.
---@param cleanup? fun(value: any, reason?: string)
---@return any value
function EffectScope:own(value, cleanup)
  assert(value ~= nil, "EffectScope cannot own nil")
  if self:check() then
    self:_dispose(value, cleanup)
    return value
  end
  self.entries[#self.entries + 1] = { value = value, cleanup = cleanup, active = true }
  return value
end

---@param value any
---@return boolean removed
function EffectScope:disown(value)
  for _, entry in ipairs(self.entries) do
    if entry.active and entry.value == value then
      entry.active = false
      return true
    end
  end
  return false
end

---@param callback fun(scope: diffview.EffectScope, reason?: string)
function EffectScope:listen(callback)
  if self:check() then
    callback(self, self.reason)
  else
    self.listeners[#self.listeners + 1] = callback
  end
end

---@private
---@param value any
---@param cleanup? fun(value: any, reason?: string)
function EffectScope:_dispose(value, cleanup)
  if cleanup then
    cleanup(value, self.reason)
    return
  end
  if type(value) == "function" then
    value(self.reason)
    return
  end
  if type(value) ~= "table" and type(value) ~= "userdata" then
    return
  end
  for _, method in ipairs({ "release", "close", "cancel", "kill", "destroy" }) do
    if type(value[method]) == "function" then
      value[method](value)
      return
    end
  end
end

---Close the scope and everything it owns. Cleanup failures never prevent the
---remaining effects from being released.
---@param reason? string
---@return string[] errors
function EffectScope:close(reason)
  if self.state == "closed" or self.state == "closing" then
    return {}
  end
  self.state = "closing"
  self.reason = reason
  local errors = {}
  local function safely(callback)
    local ok, err = pcall(callback)
    if not ok then
      errors[#errors + 1] = tostring(err)
    end
  end

  local listeners = self.listeners
  self.listeners = {}
  for _, listener in ipairs(listeners) do
    safely(function()
      listener(self, reason)
    end)
  end

  for i = #self.children, 1, -1 do
    local child_errors = self.children[i]:close(reason)
    vim.list_extend(errors, child_errors)
  end
  self.children = {}

  for i = #self.entries, 1, -1 do
    local entry = self.entries[i]
    if entry.active then
      entry.active = false
      safely(function()
        self:_dispose(entry.value, entry.cleanup)
      end)
    end
  end
  self.entries = {}
  self.state = "closed"
  return errors
end

-- Signal-compatible spelling for lifecycle callers.
EffectScope.send = EffectScope.close

return EffectScope
