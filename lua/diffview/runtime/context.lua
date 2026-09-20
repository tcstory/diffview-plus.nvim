--- runtime/context.lua
---
--- Responsibility:  Provide module-level access to the two shared singletons
---                  that used to live on `_G.DiffviewGlobal`:
---                    • `logger`  — the plugin-wide Logger instance
---                    • `emitter` — the plugin-wide EventEmitter instance
---
---                  This module is the Phase 2 bridge: callers can switch
---                  from `DiffviewGlobal.logger` to `ctx.logger` without
---                  waiting for the full DiffviewGlobal deletion in Phase 2B.
---
--- Migration guide:
---   Before:  local logger = DiffviewGlobal.logger
---   After:   local ctx    = require("diffview.runtime.context")
---            ...
---            ctx.logger:info(...)
---
--- Owns:      The singleton instances once they are initialised.
--- Does NOT own: The Logger and EventEmitter classes — those stay in
---               diffview.logger and diffview.events respectively.
---
--- Init contract:
---   `context.init(logger, emitter)` MUST be called exactly once from
---   `bootstrap.lua` after the Logger and EventEmitter are constructed.
---   All other modules must call `require("diffview.runtime.context")`
---   after bootstrap has completed (i.e., from inside a function body or
---   lazy-module accessor, never at module-load time).
---
--- Neovim API used: none.
--- Lua API used: none.

---@class diffview.Context
---@field logger Logger
---@field emitter EventEmitter
local M = {}

--- True once `init()` has been called.
local _initialised = false

--- Initialise the context with the plugin-wide singleton instances.
--- Called once by bootstrap.lua immediately after constructing Logger and
--- EventEmitter.  Calling this a second time raises an error.
---@param logger Logger
---@param emitter EventEmitter
function M.init(logger, emitter)
  if _initialised then
    error("[diffview.runtime.context] init() called more than once", 2)
  end
  M.logger = logger
  M.emitter = emitter
  _initialised = true
end

--- True when the context has been initialised and is safe to use.
---@return boolean
function M.is_ready()
  return _initialised
end

return M
