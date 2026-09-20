--- runtime/action_registry.lua
---
--- Responsibility:  Stable ActionRegistry — the single source of truth for
---                  every interactive action in diffview+.
---
---                  An "action" is any operation the user can trigger:
---                    • via a keymap
---                    • via the action palette
---                    • via a toolbar button
---                    • via the public Lua API (`require("diffview").actions.*`)
---
---                  The registry owns:
---                    • action ID (stable string, used in keymaps and config)
---                    • human-readable label and description
---                    • category (diff | history | merge | navigation | layout | file)
---                    • availability predicate (given current view/context)
---                    • execute function
---                    • danger flag (requires confirmation before execution)
---
---  Phase 3 roll-out strategy:
---    1. Register actions here with their metadata.
---    2. actions.lua functions become thin wrappers that call registry.execute().
---    3. keymaps, toolbar, palette all query the registry by ID.
---    4. actions.lua is deleted once all callers migrate to registry IDs.
---
---  Neovim API used: none (pure Lua).

---@enum diffview.ActionCategory
local ActionCategory = {
  DIFF       = "diff",
  HISTORY    = "history",
  MERGE      = "merge",
  NAVIGATION = "navigation",
  LAYOUT     = "layout",
  FILE       = "file",
  VIEW       = "view",
}

---@class diffview.ActionSpec
---@field id         string              # Stable unique identifier, e.g. "diff.goto_file"
---@field label      string              # Short human-readable name for toolbar/palette
---@field desc       string              # One-sentence description for help/tooltip
---@field category   diffview.ActionCategory
---@field available? fun(view: any): boolean  # Returns false to hide/disable the action
---@field execute    fun(...)            # The implementation
---@field danger?    boolean             # If true, UI asks for confirmation before execute

---@class diffview.ActionRegistry
local M = {}

---@type { [string]: diffview.ActionSpec }
local _actions = {}

M.ActionCategory = ActionCategory

--- Register an action.  Raises if the ID is already registered.
---@param spec diffview.ActionSpec
function M.register(spec)
  assert(type(spec.id) == "string" and spec.id ~= "", "action id must be a non-empty string")
  assert(type(spec.execute) == "function", "action.execute must be a function")
  if _actions[spec.id] then
    error(string.format("[ActionRegistry] duplicate action id: %q", spec.id), 2)
  end
  _actions[spec.id] = spec
end

--- Register multiple actions at once.
---@param specs diffview.ActionSpec[]
function M.register_all(specs)
  for _, spec in ipairs(specs) do
    M.register(spec)
  end
end

--- Retrieve a registered action by ID.  Returns nil when not found.
---@param id string
---@return diffview.ActionSpec?
function M.get(id)
  return _actions[id]
end

--- Execute an action by ID.
--- Raises when the action is not found.
--- When `available` returns false for the current view, the call is a no-op.
---@param id string
---@param view? any  # Current view, forwarded to available() check
---@param ... any    # Additional arguments forwarded to execute()
function M.execute(id, view, ...)
  local spec = _actions[id]
  if not spec then
    error(string.format("[ActionRegistry] unknown action id: %q", id), 2)
  end
  if spec.available and not spec.available(view) then
    return
  end
  spec.execute(...)
end

--- Return all registered actions, optionally filtered by category.
---@param category? diffview.ActionCategory
---@return diffview.ActionSpec[]
function M.list(category)
  local result = {}
  for _, spec in pairs(_actions) do
    if not category or spec.category == category then
      result[#result + 1] = spec
    end
  end
  table.sort(result, function(a, b) return a.id < b.id end)
  return result
end

--- Check whether an action is available for the given view.
---@param id string
---@param view? any
---@return boolean
function M.is_available(id, view)
  local spec = _actions[id]
  if not spec then return false end
  if spec.available then return spec.available(view) end
  return true
end

--- Clear all registrations.  For use in tests only.
---@package
function M._reset()
  _actions = {}
end

return M
