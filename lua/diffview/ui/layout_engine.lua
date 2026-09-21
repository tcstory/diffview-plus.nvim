---Creates the windows declared by a LayoutSpec and reuses valid slot windows.

local api = vim.api

---@class diffview.LayoutEngine
local LayoutEngine = {}
LayoutEngine.__index = LayoutEngine

---@return diffview.LayoutEngine
function LayoutEngine.new()
  return setmetatable({}, LayoutEngine)
end

---@param spec diffview.LayoutSpec
---@param pivot integer
---@param slots table<string, Window>
---@param window_factory fun(symbol: string, winid: integer): Window
---@return Window[]
function LayoutEngine:apply(spec, pivot, slots, window_factory)
  assert(api.nvim_win_is_valid(pivot), "layout engine requires a valid pivot")
  local all_valid = true
  for _, slot in ipairs(spec.slots) do
    local win = slots[slot.symbol]
    all_valid = all_valid and win ~= nil and win.id ~= nil and api.nvim_win_is_valid(win.id)
  end
  if not all_valid then
    for _, win in pairs(slots) do
      if win.id ~= pivot then
        win:close(true)
      end
    end
    for _, slot in ipairs(spec.slots) do
      api.nvim_win_call(pivot, function()
        vim.cmd(slot.command)
        local winid = api.nvim_get_current_win()
        local win = slots[slot.symbol]
        if win then
          win:set_id(winid)
        else
          slots[slot.symbol] = window_factory(slot.symbol, winid)
        end
      end)
    end
    api.nvim_win_close(pivot, true)
  elseif pivot ~= slots[spec.order[1]].id and api.nvim_win_is_valid(pivot) then
    api.nvim_win_close(pivot, true)
  end
  local ordered = {}
  for _, symbol in ipairs(spec.order) do
    ordered[#ordered + 1] = slots[symbol]
  end
  return ordered
end

return LayoutEngine
