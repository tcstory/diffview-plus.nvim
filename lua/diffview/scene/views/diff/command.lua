---Explicit commands accepted by DiffView.
---External signals and ActionRegistry entries dispatch these intents instead
---of invoking view mutations directly.

local M = {}

---@enum DiffCommandType
M.Type = {
  REFRESH = "refresh",
  STAGE_ALL = "stage_all",
  UNSTAGE_ALL = "unstage_all",
  TOGGLE_STAGE = "toggle_stage_entry",
  RESTORE = "restore_entry",
  FILTER = "filter_files",
  LISTING_STYLE = "listing_style",
  FLATTEN_DIRS = "toggle_flatten_dirs",
  HIDE_REVIEWED = "toggle_hide_selected",
}

local event_for = {
  [M.Type.STAGE_ALL] = "stage_all",
  [M.Type.UNSTAGE_ALL] = "unstage_all",
  [M.Type.TOGGLE_STAGE] = "toggle_stage_entry",
  [M.Type.RESTORE] = "restore_entry",
  [M.Type.LISTING_STYLE] = "listing_style",
  [M.Type.FLATTEN_DIRS] = "toggle_flatten_dirs",
  [M.Type.HIDE_REVIEWED] = "toggle_hide_selected",
}

---@class DiffCommand
---@field type DiffCommandType
---@field source? "user"|"index"|"gitsigns"|"buffer"
---@field opts? table

---@param view DiffView
---@param command DiffCommand
---@param callback? fun(err?: string[])
function M.execute(view, command, callback)
  if command.type == M.Type.REFRESH then
    return view:update_files(command.opts, callback)
  end
  if command.type == M.Type.FILTER then
    vim.ui.input({ prompt = "Filter files: ", default = view.store.filter }, function(value)
      if value == nil then
        return
      end
      view.store:set_filter(value)
      view.panel:render()
      view.panel:redraw()
      view.panel:reconstrain_cursor()
    end)
    return
  end
  local event =
    assert(event_for[command.type], "Unknown DiffView command: " .. tostring(command.type))
  return view.emitter:emit(event, command.opts)
end

return M
