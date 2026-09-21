---Pure Git staging argv builders.

local path_args = require("diffview.vcs.path_args")
local M = {}

---@param paths string[]
---@return string[]
function M.add_args(paths)
  return path_args.append({ "add" }, paths)
end

---@param paths string[]
---@return string[]
function M.reset_args(paths)
  return path_args.append({ "reset" }, paths)
end

---@param path string
---@return string[]
function M.index_entry_args(path)
  return path_args.append({ "-c", "core.quotePath=false", "ls-files", "--stage" }, { path })
end

return M
