---Immutable UI component values.
---
---A component describes presentation and intent only. Rendering owns buffers
---and extmarks; the router owns action dispatch and hit testing.

local M = {}
local values = setmetatable({}, { __mode = "k" })

---@class diffview.ComponentSegment
---@field text string
---@field hl? string

---@class diffview.Component
---@field identity string
---@field text diffview.ComponentSegment[]
---@field hl? string
---@field action? string
---@field disabled boolean
---@field tooltip? string
---@field children diffview.Component[]

local function readonly(value)
  if type(value) ~= "table" then
    return value
  end
  -- Components may be nested after they have already been frozen. Preserve
  -- the existing proxy; copying it with pairs() would lose its weak-map
  -- backing on LuaJIT, where __pairs is not guaranteed to be consulted.
  if values[value] then
    return value
  end
  local copy = {}
  for key, item in pairs(value) do
    copy[key] = readonly(item)
  end
  local proxy = setmetatable({}, {
    __index = copy,
    __newindex = function()
      error("UI components are immutable", 2)
    end,
    __len = function()
      return #copy
    end,
    __pairs = function()
      return pairs(copy)
    end,
    __ipairs = function()
      return ipairs(copy)
    end,
    __metatable = false,
  })
  values[proxy] = copy
  return proxy
end

local function value(component, key)
  local backing = values[component]
  return backing and backing[key] or component[key]
end

---@param spec { identity: string, text?: string|diffview.ComponentSegment[], hl?: string, action?: string, disabled?: boolean, tooltip?: string, children?: diffview.Component[] }
---@return diffview.Component
function M.new(spec)
  assert(type(spec.identity) == "string" and spec.identity ~= "", "component identity is required")
  local segments = spec.text or {}
  if type(segments) == "string" then
    segments = { { text = segments, hl = spec.hl } }
  end
  return readonly({
    identity = spec.identity,
    text = segments,
    hl = spec.hl,
    action = spec.action,
    disabled = spec.disabled == true,
    tooltip = spec.tooltip,
    children = spec.children or {},
  })
end

---@param component diffview.Component
---@return string
function M.text(component)
  local chunks = {}
  local segments = values[value(component, "text")] or value(component, "text") or {}
  for index = 1, #segments do
    chunks[#chunks + 1] = value(segments[index], "text")
  end
  return table.concat(chunks)
end

---@param component diffview.Component
---@return integer
function M.width(component)
  return vim.fn.strdisplaywidth(M.text(component))
end

---@param component diffview.Component
---@return diffview.Component[]
function M.children(component)
  local children = values[value(component, "children")] or value(component, "children") or {}
  local result = {}
  for index = 1, #children do
    result[index] = children[index]
  end
  return result
end

return M
