---Captures and restores a window's buffer, viewport, folds and local options.

local api = vim.api

---@class diffview.WindowLease.State
---@field bufnr integer
---@field bufname string
---@field view table
---@field options table<string, any>

---@class diffview.WindowLease
---@field winid integer
---@field original diffview.WindowLease.State?
---@field released boolean
local WindowLease = {}
WindowLease.__index = WindowLease

local tracked_options = {
  "cursorbind",
  "diff",
  "foldcolumn",
  "foldenable",
  "foldlevel",
  "foldmethod",
  "scrollbind",
  "winbar",
  "winhl",
}

---@param winid integer
---@return diffview.WindowLease
function WindowLease.new(winid)
  local self = setmetatable({ winid = winid, released = false }, WindowLease)
  self.original = self:capture()
  return self
end

---@return diffview.WindowLease.State?
function WindowLease:capture()
  if not (self.winid and api.nvim_win_is_valid(self.winid)) then
    return nil
  end
  local bufnr = api.nvim_win_get_buf(self.winid)
  local options = {}
  for _, name in ipairs(tracked_options) do
    options[name] = vim.wo[self.winid][name]
  end
  local ok, view = pcall(api.nvim_win_call, self.winid, vim.fn.winsaveview)
  if not ok then
    return nil
  end
  return {
    bufnr = bufnr,
    bufname = api.nvim_buf_get_name(bufnr),
    view = view,
    options = options,
  }
end

---@param state diffview.WindowLease.State?
---@param opts? { restore_buffer?: boolean }
---@return boolean
function WindowLease:restore(state, opts)
  if not (state and self.winid and api.nvim_win_is_valid(self.winid)) then
    return false
  end
  opts = opts or {}
  if opts.restore_buffer and api.nvim_buf_is_valid(state.bufnr) then
    api.nvim_win_set_buf(self.winid, state.bufnr)
  elseif api.nvim_win_get_buf(self.winid) ~= state.bufnr then
    return false
  end
  for name, value in pairs(state.options) do
    pcall(function()
      vim.wo[self.winid][name] = value
    end)
  end
  return pcall(api.nvim_win_call, self.winid, function()
    vim.fn.winrestview(state.view)
  end)
end

function WindowLease:release()
  if self.released then
    return
  end
  self.released = true
  self:restore(self.original, { restore_buffer = true })
end

return WindowLease
