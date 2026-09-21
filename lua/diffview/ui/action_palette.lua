---Registry-backed action palette.

local registry = require("diffview.runtime.action_registry")
local utils = require("diffview.utils")

local M = {}

---@param view? any
function M.open(view)
  view = view or require("diffview.lib").get_current_view()
  local items = registry.list()
  vim.ui.select(items, {
    prompt = "Diffview actions",
    format_item = function(spec)
      local available, reason = registry.availability(spec.id, view)
      if available then
        return ("%s — %s"):format(spec.label, spec.desc)
      end
      return ("%s — unavailable: %s"):format(spec.label, reason or "current context")
    end,
  }, function(spec)
    if not spec then
      return
    end
    local available, reason = registry.availability(spec.id, view)
    if not available then
      utils.warn(reason or "This action is unavailable in the current context.")
      return
    end
    registry.execute(spec.id, view)
  end)
end

return M
