---Registry-backed toolbar model. Rendering and mouse routing belong to Phase 4.

local registry = require("diffview.runtime.action_registry")
local component = require("diffview.ui.component")

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

---@param action_ids string[]
---@param view? any
---@return diffview.Component
function M.component(action_ids, view)
  local children = {}
  for _, item in ipairs(M.build(action_ids, view)) do
    children[#children + 1] = component.new({
      identity = "toolbar-" .. item.id,
      text = "[ " .. item.label .. " ]",
      action = item.id,
      disabled = item.disabled,
      tooltip = item.tooltip,
    })
  end
  return component.new({ identity = "toolbar", children = children })
end

return M
