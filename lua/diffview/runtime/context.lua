--- runtime/context.lua
---
--- Responsibility:  Provide module-level access to the shared singletons and
---                  configuration values that used to live on `_G.DiffviewGlobal`:
---                    • `logger`      — the plugin-wide Logger instance
---                    • `emitter`     — the plugin-wide EventEmitter instance
---                    • `debug_level` — integer 0-10 from $DEBUG_DIFFVIEW
---                    • `state`       — mutable plugin-wide state bag
---
---                  This module is the Phase 2 bridge: callers can switch from
---                  `DiffviewGlobal.*` to `ctx.*` without waiting for the full
---                  DiffviewGlobal deletion.
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
---   `context.init(opts)` MUST be called exactly once from `bootstrap.lua`
---   after the Logger and EventEmitter are constructed.  All other modules
---   must call `require("diffview.runtime.context")` after bootstrap has
---   completed (i.e., from inside a function body or lazy-module accessor,
---   never at module-load time).
---
--- Neovim API used: none.
--- Lua API used: none.

---@class diffview.Context
---@field logger Logger
---@field emitter EventEmitter
---@field debug_level integer   # 0=off  1=normal  5=loading  10=rendering+async
---@field state table           # mutable plugin-wide state bag
local M = {
  --- Pre-bootstrap safe defaults so callers can read the fields without
  --- is_ready() guards.
  debug_level = 0,
  state = {},
}

--- True once `init()` has been called.
local _initialised = false

---@class diffview.ContextInitOpts
---@field logger Logger
---@field emitter EventEmitter
---@field debug_level integer
---@field state table

--- Initialise the context with the plugin-wide singleton instances.
--- Called once by bootstrap.lua immediately after constructing Logger and
--- EventEmitter.  Calling this a second time raises an error.
---@param opts diffview.ContextInitOpts
function M.init(opts)
  if _initialised then
    error("[diffview.runtime.context] init() called more than once", 2)
  end
  M.logger      = opts.logger
  M.emitter     = opts.emitter
  M.debug_level = opts.debug_level
  M.state       = opts.state
  _initialised  = true
end

--- True when the context has been initialised and is safe to use.
---@return boolean
function M.is_ready()
  return _initialised
end

return M
