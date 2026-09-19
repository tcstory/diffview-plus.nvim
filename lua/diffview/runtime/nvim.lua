--- runtime/nvim.lua
---
--- Responsibility:  Centralised bridge for the small set of Neovim operations
---                  that genuinely require `vim.cmd` or lack a stable Lua API
---                  equivalent in Neovim 0.12.
--- Input:           Typed parameters; callers never assemble raw command strings.
--- Output:          Return values from the underlying API where applicable.
--- Owns:            Nothing — all functions are stateless wrappers.
--- Does NOT own:    Any buffer, window, or namespace state.
---
--- Neovim API used (per function — see individual annotations):
---   :h vim.cmd()
---   :h nvim_exec2()
---   :h nvim_open_tabpage()     — open a new tabpage programmatically
---   :h nvim_win_call()         — run a function in the context of a window
---   :h nvim_set_option_value() — set option with explicit scope
---   :h nvim_get_option_value() — get option with explicit scope
---
--- Guidelines for adding new functions to this file:
---   1. Only add functions here if there is NO stable Lua API equivalent.
---   2. Prefer `nvim_*` API calls over `vim.cmd` strings wherever possible.
---   3. Each function must document why `vim.cmd` is still required (if used).
---   4. Never build command strings from user/path data (injection risk).
---      Use `vim.fn.fnameescape()` for any path embedded in a command string.
---
--- Examples of operations that DO have stable API equivalents (do NOT add here):
---   - Buffer/window creation: nvim_create_buf, nvim_open_win
---   - Option access: vim.bo, vim.wo, nvim_get/set_option_value
---   - Keymap: nvim_buf_set_keymap / nvim_buf_del_keymap
---   - Highlights: nvim_set_hl, nvim_get_hl

local api = vim.api

local M = {}

--- Enable Neovim's built-in diff mode for the windows in `winids`.
---
--- Why vim.cmd: There is no `nvim_*` API to enable diff mode for a set of
--- windows atomically.  `diffthis` must be called in the context of each
--- window.  `:h diffthis`
---@param winids integer[]
function M.diffthis(winids)
  for _, winid in ipairs(winids) do
    -- nvim_win_call runs the callback in the context of `winid` so that
    -- `diffthis` affects the correct window.  :h nvim_win_call
    api.nvim_win_call(winid, function()
      vim.cmd("diffthis")
    end)
  end
end

--- Disable diff mode for a single window.
--- :h diffoff
---@param winid integer
function M.diffoff(winid)
  api.nvim_win_call(winid, function()
    vim.cmd("diffoff")
  end)
end

--- Update the diff display for all diff windows in the current tabpage.
--- :h diffupdate
function M.diffupdate()
  vim.cmd("diffupdate")
end

--- Jump to the next diff hunk in the current window.
--- Equivalent to the `]c` motion in diff mode.
--- :h ]c
---@param winid integer
function M.next_hunk(winid)
  api.nvim_win_call(winid, function()
    -- Use `silent!` so the "No more" message is suppressed when there are no
    -- more hunks — callers handle the boundary condition themselves.
    vim.cmd("silent! normal! ]c")
  end)
end

--- Jump to the previous diff hunk in the current window.
--- :h [c
---@param winid integer
function M.prev_hunk(winid)
  api.nvim_win_call(winid, function()
    vim.cmd("silent! normal! [c")
  end)
end

--- Open a new tabpage using the current buffer and return its handle.
---
--- Prefer this over `vim.cmd("tabnew")` or `vim.cmd("tab split")` because:
---   - `nvim_open_tabpage` returns the tabpage handle directly.
---   - `enter = true` makes the new tabpage current without a separate
---     `nvim_set_current_tabpage` call.
---
--- :h nvim_open_tabpage(bufnr, enter, opts)
---   bufnr = 0     → use the current buffer in the new tab
---   enter = true  → switch to the new tabpage immediately
---   opts  = {}    → no extra options
---@return integer tabpage
function M.open_tabpage()
  -- :h nvim_open_tabpage
  return api.nvim_open_tabpage(0, true, {})
end

--- Get the value of a window-scoped option.
--- :h nvim_get_option_value
---@param name string
---@param winid integer
---@return any
function M.get_win_option(name, winid)
  return api.nvim_get_option_value(name, { win = winid })
end

--- Set a window-scoped option.
--- :h nvim_set_option_value
---@param name string
---@param value any
---@param winid integer
function M.set_win_option(name, value, winid)
  api.nvim_set_option_value(name, value, { win = winid })
end

--- Get the value of a buffer-scoped option.
--- :h nvim_get_option_value
---@param name string
---@param bufnr integer
---@return any
function M.get_buf_option(name, bufnr)
  return api.nvim_get_option_value(name, { buf = bufnr })
end

--- Set a buffer-scoped option.
--- :h nvim_set_option_value
---@param name string
---@param value any
---@param bufnr integer
function M.set_buf_option(name, value, bufnr)
  api.nvim_set_option_value(name, value, { buf = bufnr })
end

return M
