local api = vim.api

local M = {}

---@class MergeProjection
---@field namespace integer
---@field buffers table<string, integer>
---@field marks table<string, table<string, integer>>
local MergeProjection = {}
MergeProjection.__index = MergeProjection

function MergeProjection.new()
  return setmetatable({
    namespace = api.nvim_create_namespace("diffview_transactional_merge"),
    buffers = {},
    marks = {},
  }, MergeProjection)
end

---@param path string
---@param bufnr integer
function MergeProjection:attach(path, bufnr)
  self.buffers[path] = bufnr
  self.marks[path] = self.marks[path] or {}
  api.nvim_buf_clear_namespace(bufnr, self.namespace, 0, -1)
  self.marks[path] = {}
end

---@param path string
---@param conflict MergeSession.Conflict
---@return integer, integer
function MergeProjection:range(path, conflict)
  local bufnr = self.buffers[path]
  local mark = self.marks[path] and self.marks[path][conflict.identity]
  if bufnr and mark and api.nvim_buf_is_valid(bufnr) then
    local position = api.nvim_buf_get_extmark_by_id(bufnr, self.namespace, mark, { details = true })
    if position and #position > 0 then
      return position[1], position[3].end_row or position[1]
    end
  end
  return conflict.start_line - 1, conflict.end_line
end

---@param path string
---@param conflict MergeSession.Conflict
function MergeProjection:place(path, conflict)
  local bufnr = self.buffers[path]
  if not (bufnr and api.nvim_buf_is_valid(bufnr)) then
    return
  end
  local start_row, end_row = self:range(path, conflict)
  local old = self.marks[path] and self.marks[path][conflict.identity]
  if old then
    pcall(api.nvim_buf_del_extmark, bufnr, self.namespace, old)
  end
  local status = conflict.resolved and (" ✔ %s "):format(conflict.choice or "manual")
    or (" Unresolved %d "):format(conflict.id)
  local choices = { "ours", "base", "theirs", "all", "manual" }
  local virt_line =
    { { status, conflict.resolved and "DiffviewFilePanelInsertions" or "DiagnosticError" } }
  for _, choice in ipairs(choices) do
    virt_line[#virt_line + 1] = { " ", "Normal" }
    local selected = conflict.resolved and conflict.choice == choice
    virt_line[#virt_line + 1] = {
      selected and ("[ ✔ %s ]"):format(choice:upper()) or ("[ %s ]"):format(choice:upper()),
      choice == "theirs" and "DiffviewFilePanelDeletions" or "DiffviewFilePanelInsertions",
    }
  end
  self.marks[path][conflict.identity] =
    api.nvim_buf_set_extmark(bufnr, self.namespace, start_row, 0, {
      end_row = end_row,
      end_col = 0,
      virt_lines = { virt_line },
      virt_lines_above = true,
      right_gravity = false,
      end_right_gravity = true,
    })
end

---@param path string
function MergeProjection:clear(path)
  local bufnr = self.buffers[path]
  if bufnr and api.nvim_buf_is_valid(bufnr) then
    api.nvim_buf_clear_namespace(bufnr, self.namespace, 0, -1)
  end
  self.marks[path] = {}
end

M.MergeProjection = MergeProjection

return M
