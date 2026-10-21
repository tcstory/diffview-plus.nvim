---Confirmation dialog component and presentation adapter.

local component = require("diffview.ui.component")

local M = {}

---@param prompt string
---@return diffview.Component
function M.component(prompt)
  return component.new({
    identity = "confirm-dialog",
    text = prompt,
    tooltip = "Choose Yes to perform this action.",
  })
end

---@param prompt string
---@return boolean
function M.ask(prompt)
  M.component(prompt)
  return vim.fn.confirm(prompt, "&Yes\n&No", 1, "Warning") == 1
end

return M
