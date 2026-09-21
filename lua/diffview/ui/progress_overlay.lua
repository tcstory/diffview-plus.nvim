---Progress overlay component backed by Neovim's ephemeral progress messages.

local component = require("diffview.ui.component")

local M = {}
local next_id = 1
local active = {}

---@param message string
---@return integer
function M.show(message)
  local id = next_id
  next_id = next_id + 1
  active[id] = component.new({ identity = "progress-" .. id, text = message })
  vim.api.nvim_echo({ { message, "Comment" } }, false, { kind = "progress" })
  return id
end

---@param id integer
---@param message string
function M.update(id, message)
  if not active[id] then
    return false
  end
  active[id] = component.new({ identity = "progress-" .. id, text = message })
  vim.api.nvim_echo({ { message, "Comment" } }, false, { kind = "progress" })
  return true
end

---@param id integer
function M.finish(id)
  active[id] = nil
  if not next(active) then
    vim.api.nvim_echo({}, false, { kind = "progress" })
  end
end

---@param id integer
---@return diffview.Component?
function M.get(id)
  return active[id]
end

return M
