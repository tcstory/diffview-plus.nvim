---Pure Git status argv builders and NUL-delimited diff parsers.

local M = {}

---@param output string|string[]
---@return string
local function output_text(output)
  if type(output) == "table" then
    return table.concat(output, "\n")
  end
  return output
end

---@param base string[]
---@param rev_args string[]
---@param stat_flag "--name-status"|"--numstat"
---@param rename_flag? string
---@return string[]
function M.diff_args(base, rev_args, stat_flag, rename_flag)
  local args = vim.list_extend(vim.deepcopy(base), { "diff", "-z" })
  if rename_flag then
    args[#args + 1] = rename_flag
  end
  vim.list_extend(args, { "--ignore-submodules", stat_flag })
  vim.list_extend(args, rev_args)
  return args
end

---@class GitStatus.NameEntry
---@field status string
---@field name string
---@field oldname? string

---@param output string|string[]
---@return GitStatus.NameEntry[]
function M.parse_name_status(output)
  local raw = output_text(output)
  local fields = vim.split(raw, "\0", { plain = true })
  local entries = {}
  local i = 1
  while i <= #fields do
    local field = fields[i]
    if field == "" then
      i = i + 1
    else
      local status = field:sub(1, 1):gsub("%s", " ")
      local name = fields[i + 1]
      local oldname
      if status == "R" or status == "C" then
        oldname = name
        name = fields[i + 2]
        i = i + 3
      else
        i = i + 2
      end
      if name then
        entries[#entries + 1] = { status = status, name = name, oldname = oldname }
      end
    end
  end
  return entries
end

---@param output string|string[]
---@return table<integer, { additions: integer, deletions: integer }>
---@return integer count
function M.parse_numstat(output)
  local raw = output_text(output)
  local fields = vim.split(raw, "\0", { plain = true })
  local entries = {}
  local count = 0
  local i = 1
  while i <= #fields do
    local field = fields[i]
    if field == "" then
      i = i + 1
    else
      local additions, deletions, path = field:match("^([%d-]+)\t([%d-]+)\t(.*)")
      if not additions then
        i = i + 1
      else
        i = path == "" and i + 3 or i + 1
        count = count + 1
        local add_num, delete_num = tonumber(additions), tonumber(deletions)
        if add_num and delete_num then
          entries[count] = { additions = add_num, deletions = delete_num }
        end
      end
    end
  end
  return entries, count
end

return M
