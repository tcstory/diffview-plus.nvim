---Confirmation dialog component and presentation adapter.

local component = require("diffview.ui.component")

local M = {}

---@param prompt string
---@return diffview.Component
function M.component(prompt)
  return component.new({
    identity = "confirm-dialog",
    text = prompt,
    tooltip = "Choose Continue to perform this action.",
  })
end

---@param prompt string
---@return boolean
function M.ask(prompt)
  M.component(prompt)
  return vim.fn.confirm(prompt, "&Cancel\n&Continue", 1, "Warning") == 2
end

return M
