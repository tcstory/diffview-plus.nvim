---Pure Git history argv construction. Parsing lives in `git.parser`.

local path_args = require("diffview.vcs.path_args")

local M = {}

---@param command string[]
---@param args string[]
---@param paths? string[]
---@return string[]
function M.log_args(command, args, paths)
  local result = vim.list_extend(vim.deepcopy(command), {
    "log",
    "--no-show-signature",
    "--first-parent",
    "--stat",
  })
  vim.list_extend(result, args)
  vim.list_extend(result, path_args.git_literals(paths))
  return result
end

return M
