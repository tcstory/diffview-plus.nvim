---Literal-safe argv construction for VCS paths.
---Never returns a shell string; every path remains one process argument.

local M = {}

---@param paths string[]?
---@param transform? fun(path: string): string
---@return string[]
function M.after_separator(paths, transform)
  if not paths or #paths == 0 then
    return {}
  end
  local args = { "--" }
  for _, path in ipairs(paths) do
    args[#args + 1] = transform and transform(path) or path
  end
  return args
end

---@param args string[]
---@param paths string[]?
---@param transform? fun(path: string): string
---@return string[]
function M.append(args, paths, transform)
  local result = vim.deepcopy(args)
  vim.list_extend(result, M.after_separator(paths, transform))
  return result
end

---@param paths string[]?
---@return string[]
function M.git_literals(paths)
  return M.after_separator(paths, function(path)
    return ":(literal)" .. path
  end)
end

---@param revision string?
---@param path string
---@return string
function M.git_object(revision, path)
  return (revision or "") .. ":" .. path
end

return M
