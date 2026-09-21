---Declarative description of a layout's slots and constraints.

---@class diffview.LayoutSpec.Slot
---@field symbol string
---@field command string

---@class diffview.LayoutSpec
---@field name string
---@field slots diffview.LayoutSpec.Slot[]
---@field order string[]
---@field constraints table
local LayoutSpec = {}
LayoutSpec.__index = LayoutSpec

---@param name string
---@param slots diffview.LayoutSpec.Slot[]
---@param order string[]
---@param constraints? table
---@return diffview.LayoutSpec
function LayoutSpec.new(name, slots, order, constraints)
  assert(type(name) == "string" and name ~= "", "layout spec requires a name")
  local seen = {}
  for _, slot in ipairs(slots) do
    assert(not seen[slot.symbol], "duplicate layout slot: " .. slot.symbol)
    seen[slot.symbol] = true
  end
  for _, symbol in ipairs(order) do
    assert(seen[symbol], "layout order references an unknown slot: " .. symbol)
  end
  return setmetatable({
    name = name,
    slots = vim.deepcopy(slots),
    order = vim.deepcopy(order),
    constraints = vim.deepcopy(constraints or {}),
  }, LayoutSpec)
end

---@param name string
---@param win_specs { [1]: string, [2]: string }[]
---@param order string[]
---@return diffview.LayoutSpec
function LayoutSpec.from_legacy(name, win_specs, order)
  local slots = {}
  for _, item in ipairs(win_specs) do
    slots[#slots + 1] = { symbol = item[1], command = item[2] }
  end
  return LayoutSpec.new(name, slots, order)
end

return LayoutSpec
