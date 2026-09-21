---Action-ID keymap adapter.
---
---Config stores stable action IDs.  This module resolves them only at the
---Neovim boundary, keeping the registry as the single source of labels,
---availability and execution behaviour.

local registry = require("diffview.runtime.action_registry")

local M = {}

---@param mapping DiffviewKeymapEntry
---@return DiffviewKeymapEntry
function M.resolve(mapping)
  local resolved = vim.deepcopy(mapping)
  local rhs = resolved[3]
  local id
  if type(rhs) == "string" and registry.get(rhs) then
    id = rhs
  end
  if id then
    local spec = assert(registry.get(id))
    resolved[3] = registry.callback(id)
    resolved[4] = vim.tbl_extend("keep", resolved[4] or {}, { desc = spec.desc })
    resolved[5] = id
  elseif type(rhs) == "function" then
    resolved[5] = registry.id_for(rhs)
  end
  return resolved
end

---@param mappings DiffviewKeymapEntry[]
---@return DiffviewKeymapEntry[]
function M.resolve_all(mappings)
  local result = {}
  for _, mapping in ipairs(mappings or {}) do
    result[#result + 1] = M.resolve(mapping)
  end
  return result
end

return M
