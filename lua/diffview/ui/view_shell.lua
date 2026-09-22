---Lifecycle and resource owner shared by all view implementations.
---
---`View` remains a compatibility facade for the concrete view classes, while
---this object owns the state that decides whether interactive work is safe.

---@class diffview.ViewShell
---@field owner View
---@field state "idle"|"loading"|"ready"|"closing"|"closed"
---@field effects diffview.EffectScope
local ViewShell = {}
ViewShell.__index = ViewShell

local EffectScope = require("diffview.runtime.effect_scope")

---@param owner View
---@return diffview.ViewShell
function ViewShell.new(owner)
  return setmetatable({ owner = owner, state = "idle", effects = EffectScope.new() }, ViewShell)
end

function ViewShell:begin_loading()
  self.state = "loading"
end

function ViewShell:mark_ready()
  if self.state ~= "closing" and self.state ~= "closed" then
    self.state = "ready"
  end
end

---@return boolean available
---@return string? reason
function ViewShell:can_execute()
  local owner_closing = self.owner.closing
    and type(self.owner.closing.check) == "function"
    and self.owner.closing:check()
  if owner_closing or self.state == "closing" or self.state == "closed" then
    return false, "View is closing"
  end
  -- Concrete views already expose `ready`; honour it as the compatibility
  -- signal while they migrate their async bootstrap into ViewShell.
  if self.owner.ready then
    self:mark_ready()
  end
  if self.state ~= "ready" then
    return false, "View is loading"
  end
  return true, nil
end

---@param resource any
---@param cleanup? fun(resource: any, reason?: string)
---@return any resource
function ViewShell:own(resource, cleanup)
  return self.effects:own(resource, cleanup)
end

---@param resource table
function ViewShell:disown(resource)
  return self.effects:disown(resource)
end

function ViewShell:begin_close()
  self.state = "closing"
end

function ViewShell:close()
  self:begin_close()
  self.effects:close("View closed")
  self.state = "closed"
end

return ViewShell
