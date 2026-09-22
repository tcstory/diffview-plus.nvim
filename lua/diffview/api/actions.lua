---Public ActionRegistry API.

-- Register every built-in action before exposing the registry.
require("diffview.actions.builtins")

local registry = require("diffview.runtime.action_registry")

local M = {}

---@param id string
---@return diffview.ActionSpec?
function M.get(id)
  return registry.get(id)
end

---@param category? diffview.ActionCategory
---@return diffview.ActionSpec[]
function M.list(category)
  return registry.list(category)
end

---@param id string
---@param ... any
function M.execute(id, ...)
  local view = require("diffview.lib").get_current_view()
  return registry.execute(id, view, ...)
end

---@param id string
---@return function
function M.callback(id)
  return registry.callback(id)
end

return M
