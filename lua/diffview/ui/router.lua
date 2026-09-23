---Single UI input router for buffer components, virtual lines and winbars.

local actions = require("diffview.runtime.action_registry")
local utils = require("diffview.utils")

local api = vim.api
local M = {}

local next_id = 1
---@type table<integer, table>
local routes = {}
---@type table<any, table<integer, true>>
local owners = setmetatable({}, { __mode = "k" })

local function remember(owner, id)
  if not owner then
    return
  end
  owners[owner] = owners[owner] or {}
  owners[owner][id] = true
end

---@class diffview.UIRoute
---@field id? integer
---@field owner? any
---@field action? string
---@field handler? fun(route: diffview.UIRoute): any
---@field bufnr? integer
---@field line? integer 1-based buffer line.
---@field start_col? integer 1-based display cell, inclusive.
---@field end_col? integer 1-based display cell, inclusive.
---@field virtual? boolean
---@field cursor_line? integer
---@field disabled? boolean
---@field tooltip? string

---@param route diffview.UIRoute
---@return integer
function M.register(route)
  assert(route.action or route.handler, "route requires an action or handler")
  local id = next_id
  next_id = next_id + 1
  route.id = id
  routes[id] = route
  remember(route.owner, id)
  return id
end

---@param id integer
function M.unregister(id)
  local route = routes[id]
  if route and route.owner and owners[route.owner] then
    owners[route.owner][id] = nil
  end
  routes[id] = nil
end

---@param owner any
function M.unregister_owner(owner)
  if owner == nil then
    return
  end
  for id in pairs(owners[owner] or {}) do
    routes[id] = nil
  end
  owners[owner] = nil
end

---@return integer
function M.size()
  local count = 0
  for _ in pairs(routes) do
    count = count + 1
  end
  return count
end

---@param route diffview.UIRoute
---@return any
local function execute(route)
  if route.disabled then
    if route.tooltip then
      utils.warn(route.tooltip)
    end
    return false
  end
  if route.cursor_line and route.bufnr then
    local winid = vim.fn.bufwinid(route.bufnr)
    if winid and winid > 0 then
      pcall(api.nvim_win_set_cursor, winid, { route.cursor_line, 0 })
    end
  end
  if route.handler then
    return route.handler(route)
  end
  local view = require("diffview.lib").get_current_view()
  return actions.execute(route.action, view)
end

---@param id integer
---@return any
function M.dispatch_id(id)
  local route = routes[tonumber(id)]
  if route then
    return execute(route)
  end
end

local function is_virtual_click(mouse, route)
  if not route.virtual then
    return true
  end
  local winid = mouse.winid
  if not (winid and winid > 0 and route.line) then
    return false
  end
  local screen = vim.fn.screenpos(winid, route.line, 1)
  return screen and screen.row > 0 and mouse.screenrow and mouse.screenrow < screen.row
end

---Apply the part of native mouse handling that an intercepted click needs
---before its action runs. In particular, panel actions resolve their item
---from the focused window and its cursor.
---@param mouse table
local function focus_mouse_target(mouse)
  if not (mouse.winid and mouse.winid > 0 and api.nvim_win_is_valid(mouse.winid)) then
    return
  end
  pcall(api.nvim_set_current_win, mouse.winid)
  if mouse.line and mouse.line > 0 and api.nvim_win_is_valid(mouse.winid) then
    pcall(api.nvim_win_set_cursor, mouse.winid, { mouse.line, 0 })
  end
end

---@param source "keyboard"|"mouse"
---@param bufnr integer
---@param fallback_action? string
---@param mouse? table Pre-read mouse position, used when routing across buffers.
---@return any
function M.dispatch_buffer(source, bufnr, fallback_action, mouse)
  local line, cell
  if source == "mouse" then
    mouse = mouse or vim.fn.getmousepos()
    if mouse.winid <= 0 or api.nvim_win_get_buf(mouse.winid) ~= bufnr then
      return false
    end
    line = mouse.line
    local info = vim.fn.getwininfo(mouse.winid)[1]
    cell = mouse.wincol - (info and info.textoff or 0)
    for _, route in pairs(routes) do
      if route.bufnr == bufnr and route.line == line and is_virtual_click(mouse, route) then
        local first = route.start_col or 1
        local last = route.end_col or math.huge
        if cell >= first and cell <= last then
          focus_mouse_target(mouse)
          execute(route)
          return true
        end
      end
    end
  else
    local winid = vim.fn.bufwinid(bufnr)
    line = winid > 0 and api.nvim_win_get_cursor(winid)[1] or 0
    for _, route in pairs(routes) do
      if route.bufnr == bufnr and route.line == line and not route.virtual then
        return execute(route)
      end
    end
  end
  if fallback_action then
    if source == "mouse" and mouse then
      focus_mouse_target(mouse)
    end
    local view = require("diffview.lib").get_current_view()
    local result = actions.execute(fallback_action, view)
    -- A mouse fallback is handled even when the action itself has no return
    -- value. This prevents an expression mapping from replaying the click and
    -- executing both the action and native mouse handling.
    return source == "mouse" and true or result
  end
  return false
end

---Route a click by its actual target window rather than the buffer whose
---local mapping happened to be active before Neovim processes the click.
---This is important when clicking directly from one Diffview pane into a
---button in another pane: mapping lookup still belongs to the old buffer.
---@param mapped_bufnr integer Buffer that supplied the local mapping.
---@param fallback_action? string Only applies when the click targets mapped_bufnr.
---@return boolean handled
function M.dispatch_mouse(mapped_bufnr, fallback_action)
  local mouse = vim.fn.getmousepos()
  if not (mouse.winid and mouse.winid > 0 and api.nvim_win_is_valid(mouse.winid)) then
    return false
  end
  local target_bufnr = api.nvim_win_get_buf(mouse.winid)
  local fallback = target_bufnr == mapped_bufnr and fallback_action or nil
  return M.dispatch_buffer("mouse", target_bufnr, fallback, mouse) == true
end

---@param source "keyboard"|"mouse"
---@param bufnr integer
---@param fallback_action? string
---@return function
function M.callback(source, bufnr, fallback_action)
  return function()
    if source == "mouse" then
      -- Callers install this as an expression mapping. An unhandled click is
      -- returned to Neovim so ordinary focus/cursor behaviour is preserved.
      return M.dispatch_mouse(bufnr, fallback_action) and "" or "<LeftMouse>"
    end
    return M.dispatch_buffer(source, bufnr, fallback_action)
  end
end

---@param id integer
---@param label string
---@param hl? string
---@return string
function M.winbar(id, label, hl)
  local prefix = hl and ("%%#%s#"):format(hl) or ""
  return ("%s%%%d@v:lua.DiffviewUIRouter@%s%%X%%*"):format(prefix, id, label)
end

---Return display-cell spans for component segments. Handles wide and combining
---characters through `strdisplaywidth`; RTL text remains a logical span.
---@param segments diffview.ComponentSegment[]
---@param start_col? integer
---@return { start_col: integer, end_col: integer, text: string }[]
function M.segment_spans(segments, start_col)
  local col = start_col or 1
  local spans = {}
  for _, segment in ipairs(segments) do
    local width = vim.fn.strdisplaywidth(segment.text)
    spans[#spans + 1] =
      { start_col = col, end_col = col + math.max(width - 1, 0), text = segment.text }
    col = col + width
  end
  return spans
end

function M._reset()
  routes = {}
  owners = setmetatable({}, { __mode = "k" })
  next_id = 1
end

_G.DiffviewUIRouter = function(minwid)
  local id = tonumber(minwid)
  if id then
    return M.dispatch_id(id)
  end
end

return M
