---Projection helpers for immutable UI components.

local component = require("diffview.ui.component")
local router = require("diffview.ui.router")

local M = {}

---Render a component's children as a clickable winbar. Routes are owned by
---`owner` and therefore removed with the panel lifecycle.
---@param root diffview.Component
---@param owner any
---@return string
function M.winbar(root, owner)
  local chunks = {}
  for _, child in ipairs(component.children(root)) do
    local id = router.register({
      owner = owner,
      action = child.action,
      disabled = child.disabled,
      tooltip = child.tooltip,
    })
    chunks[#chunks + 1] =
      router.winbar(id, component.text(child), child.disabled and "DiffviewDim1" or child.hl)
  end
  return table.concat(chunks, " ")
end

return M
