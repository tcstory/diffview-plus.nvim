---Central confirmation service for dangerous actions.
---
---Phase 3 keeps this deliberately small.  Action handlers declare danger in
---the registry; callers never open their own confirmation prompt.

local M = {}

---@type fun(prompt: string): boolean
local handler = function(prompt)
  return vim.fn.confirm(prompt, "&Cancel\n&Continue", 1, "Warning") == 2
end

---@param prompt string
---@return boolean
function M.ask(prompt)
  return handler(prompt)
end

---@param replacement? fun(prompt: string): boolean
function M._set_handler(replacement)
  handler = replacement
    or function(prompt)
      return vim.fn.confirm(prompt, "&Cancel\n&Continue", 1, "Warning") == 2
    end
end

return M
