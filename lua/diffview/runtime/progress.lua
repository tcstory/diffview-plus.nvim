--- runtime/progress.lua
---
--- Responsibility:  Display and clear Neovim progress messages for long-running
---                  VCS / history / merge operations.
--- Input:           A message string and an optional "kind" tag.
--- Output:          Side-effects only (messages area update).
--- Owns:            Nothing persistent — each call is stateless.
--- Does NOT own:    The operation being tracked; callers own the lifecycle.
---
--- Neovim API used:
---   :h nvim_echo()          — echo with kind tag; kind="progress" shows in
---                             the message area without adding to message history.
---   :h progress-message     — Neovim 0.12 progress message semantics:
---                             a message with kind="progress" replaces the
---                             previous progress message on the same line.
---
--- Why this module exists:
---   The old code uses plain `vim.cmd("echo '...'")` or custom loading text,
---   which adds entries to `:messages` history and cannot be cleared cleanly.
---   Neovim 0.12 introduced the `progress` message kind, which the status-line
---   / command-line area treats as ephemeral: it is overwritten by the next
---   progress message and cleared by `""`.  This module encapsulates that
---   pattern so callers do not need to know about the `nvim_echo` opts table.

local M = {}
local overlay = require("diffview.ui.progress_overlay")
local current

--- Show a progress message in the command-line area.
---
--- The message is ephemeral: it does not appear in `:messages` history and
--- is overwritten by the next `show()` or cleared by `clear()`.
---
--- Must be called on the main thread (not inside a `vim.system` callback).
--- Use `vim.schedule(function() progress.show(...) end)` from async contexts.
---
--- :h nvim_echo
--- :h progress-message
---@param msg string   The message to display (prefix with a spinner or icon if desired).
---@param kind? string  Defaults to "progress".  Pass "warn" or "error" for one-off alerts.
function M.show(msg, kind)
  -- nvim_echo(chunks, history, opts)
  --   chunks: list of [text, hl_group] pairs
  --   history: false → do not add to message history
  --   opts.kind: "progress" → ephemeral status-line message
  if kind and kind ~= "progress" then
    vim.api.nvim_echo({ { msg, "Comment" } }, false, { kind = kind })
  elseif current then
    overlay.update(current, msg)
  else
    current = overlay.show(msg)
  end
end

--- Clear the current progress message.
---
--- Sends an empty progress message, which blanks the command-line area.
--- Safe to call even if no progress message was previously shown.
function M.clear()
  if current then
    overlay.finish(current)
  end
  current = nil
end

--- Show `msg`, then call `fn()`, then clear the message.
---
--- Convenience wrapper for synchronous operations where the duration is known.
--- For async operations, call `show()` / `clear()` manually at the right
--- async boundaries.
---
---@param msg string
---@param fn fun(): any
---@return any   The return value of `fn`.
function M.wrap(msg, fn)
  M.show(msg)
  local ok, result = pcall(fn)
  M.clear()
  if not ok then
    error(result, 2)
  end
  return result
end

return M
