---Reject removed configuration shapes with actionable replacements.
---Migration is intentionally finite: unsupported aliases never enter runtime config.

local M = {}

---@param user_config DiffviewConfig.user|table
function M.check(user_config)
  local removed = {}
  local function reject(value, path, replacement)
    if value ~= nil then
      removed[#removed + 1] = ("'%s' (use %s)"):format(path, replacement)
    end
  end

  reject(user_config.key_bindings, "key_bindings", "keymaps with action IDs")
  if type(user_config.keymaps) == "table" then
    local keymaps = user_config.keymaps --[[@as table]]
    reject(keymaps.disable_defaults, "keymaps.disable_defaults", "keymaps.preset = 'none'")
  end

  for _, panel_name in ipairs({ "file_panel", "file_history_panel" }) do
    local panel = user_config[panel_name]
    if type(panel) == "table" then
      reject(panel.use_icons, panel_name .. ".use_icons", "the top-level use_icons option")
      for _, option in ipairs({ "position", "width", "height" }) do
        reject(panel[option], panel_name .. "." .. option, panel_name .. ".win_config." .. option)
      end
    end
  end

  local history = user_config.file_history_panel
  local log_options = type(history) == "table" and history.log_options or nil
  if type(log_options) == "table" then
    for _, option in ipairs({
      "single_file",
      "multi_file",
      "max_count",
      "follow",
      "all",
      "merges",
      "no_merges",
      "reverse",
    }) do
      reject(
        log_options[option],
        "file_history_panel.log_options." .. option,
        "file_history_panel.log_options.<adapter>.<scope>"
      )
    end
  end

  if #removed > 0 then
    error("Removed Diffview configuration: " .. table.concat(removed, "; "), 3)
  end
end

return M
