---Reversible ownership of buffer-local state.

local api = vim.api

---@class diffview.BufferLease.SavedKeymap
---@field mode string
---@field lhs string
---@field rhs string
---@field callback? function
---@field opts table

---@class diffview.BufferLease
---@field bufnr integer
---@field saved_keymaps table<string, diffview.BufferLease.SavedKeymap>
---@field installed_keymaps table<string, { mode: string, lhs: string }>
---@field saved_options table<string, any>
---@field diagnostics_enabled? boolean
---@field inlay_hints_enabled? boolean
---@field released boolean
local BufferLease = {}
BufferLease.__index = BufferLease

---@param bufnr integer
---@param saved_keymaps? table<string, diffview.BufferLease.SavedKeymap>
---@return diffview.BufferLease
function BufferLease.new(bufnr, saved_keymaps)
  return setmetatable({
    bufnr = bufnr,
    saved_keymaps = saved_keymaps or {},
    installed_keymaps = {},
    saved_options = {},
    released = false,
  }, BufferLease)
end

---@private
---@param mode string
---@param lhs string
function BufferLease:_save_keymap(mode, lhs)
  local key = mode .. " " .. lhs
  if self.saved_keymaps[key] then
    return
  end
  for _, km in ipairs(api.nvim_buf_get_keymap(self.bufnr, mode)) do
    if km.lhs == lhs then
      self.saved_keymaps[key] = {
        mode = mode,
        lhs = lhs,
        rhs = km.rhs or "",
        callback = km.callback,
        opts = {
          buffer = self.bufnr,
          desc = km.desc,
          silent = km.silent == 1 or km.silent == true,
          noremap = km.noremap == 1 or km.noremap == true,
          nowait = km.nowait == 1 or km.nowait == true,
          expr = km.expr == 1 or km.expr == true,
        },
      }
      return
    end
  end
end

---@param modes string|string[]
---@param lhs string
---@param rhs string|function
---@param opts? table
function BufferLease:set_keymap(modes, lhs, rhs, opts)
  ---@type string[]
  local mode_list
  if type(modes) == "table" then
    mode_list = modes
  else
    mode_list = { modes }
  end
  for _, mode in ipairs(mode_list) do
    self:_save_keymap(mode, lhs)
    self.installed_keymaps[mode .. " " .. lhs] = { mode = mode, lhs = lhs }
  end
  vim.keymap.set(modes, lhs, rhs, vim.tbl_extend("force", opts or {}, { buffer = self.bufnr }))
end

---@param name string
---@param value any
function BufferLease:set_option(name, value)
  if self.saved_options[name] == nil then
    self.saved_options[name] = vim.bo[self.bufnr][name]
  end
  vim.bo[self.bufnr][name] = value
end

function BufferLease:disable_diagnostics()
  if self.diagnostics_enabled == nil then
    local ok, enabled = pcall(vim.diagnostic.is_enabled, { bufnr = self.bufnr })
    self.diagnostics_enabled = ok and enabled
    if not ok then
      self.diagnostics_enabled = true
    end
  end
  vim.diagnostic.enable(false, { bufnr = self.bufnr })
end

function BufferLease:disable_inlay_hints()
  if self.inlay_hints_enabled == nil then
    local ok, enabled = pcall(vim.lsp.inlay_hint.is_enabled, { bufnr = self.bufnr })
    self.inlay_hints_enabled = ok and enabled
    if not ok then
      self.inlay_hints_enabled = true
    end
  end
  pcall(vim.lsp.inlay_hint.enable, false, { bufnr = self.bufnr })
end

function BufferLease:release()
  if self.released then
    return
  end
  self.released = true
  if api.nvim_buf_is_valid(self.bufnr) then
    for _, mapping in pairs(self.installed_keymaps) do
      pcall(api.nvim_buf_del_keymap, self.bufnr, mapping.mode, mapping.lhs)
    end
    for _, km in pairs(self.saved_keymaps) do
      local rhs = km.callback or km.rhs
      if rhs then
        pcall(vim.keymap.set, km.mode, km.lhs, rhs, km.opts)
      end
    end
    for name, value in pairs(self.saved_options) do
      pcall(function()
        vim.bo[self.bufnr][name] = value
      end)
    end
  end
  if self.diagnostics_enabled ~= nil then
    pcall(vim.diagnostic.enable, self.diagnostics_enabled, { bufnr = self.bufnr })
  end
  if self.inlay_hints_enabled ~= nil then
    pcall(vim.lsp.inlay_hint.enable, self.inlay_hints_enabled, { bufnr = self.bufnr })
  end
end

return BufferLease
