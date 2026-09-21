---Registry-backed toolbar model. Rendering and mouse routing belong to Phase 4.

local registry = require("diffview.runtime.action_registry")

local M = {}

---@class diffview.ToolbarItem
---@field id string
---@field label string
---@field disabled boolean
---@field tooltip string

---@param action_ids string[]
---@param view? any
---@return diffview.ToolbarItem[]
function M.build(action_ids, view)
  local items = {}
  for _, id in ipairs(action_ids) do
    local spec = assert(registry.get(id), "Unknown toolbar action: " .. id)
    local available, reason = registry.availability(id, view)
    items[#items + 1] = {
      id = id,
      label = spec.label,
      disabled = not available,
      tooltip = available and spec.desc or (reason or "Unavailable in this context"),
    }
  end
  return items
end

return M
