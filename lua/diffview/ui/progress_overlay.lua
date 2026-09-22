---Progress overlay component backed by Neovim's ephemeral progress messages.

local component = require("diffview.ui.component")

local M = {}
local next_id = 1
local active = {}
local echo_ids = {}

local function echo(message, opts)
  return vim.api.nvim_echo(
    { { message, "Comment" } },
    false,
    vim.tbl_extend("force", {
      kind = "progress",
      source = "diffview",
      title = "Diffview",
    }, opts)
  )
end

---@param message string
---@return integer
function M.show(message)
  local id = next_id
  next_id = next_id + 1
  active[id] = component.new({ identity = "progress-" .. id, text = message })
  echo_ids[id] = echo(message, { status = "running" })
  return id
end

---@param id integer
---@param message string
function M.update(id, message)
  if not active[id] then
    return false
  end
  active[id] = component.new({ identity = "progress-" .. id, text = message })
  echo(message, { id = echo_ids[id], status = "running" })
  return true
end

---@param id integer
---@param status? "success"|"failed"|"cancel"
---@param message? string
function M.finish(id, status, message)
  if echo_ids[id] then
    echo(message or "Done", {
      id = echo_ids[id],
      status = status or "success",
      percent = (status == nil or status == "success") and 100 or nil,
    })
  end
  active[id] = nil
  echo_ids[id] = nil
end

---@param id integer
---@return diffview.Component?
function M.get(id)
  return active[id]
end

return M
