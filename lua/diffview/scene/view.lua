local lazy = require("diffview.lazy")

local Diff1 = lazy.access("diffview.scene.layouts.diff_1", "Diff1") ---@type Diff1|LazyModule
local Diff2Hor = lazy.access("diffview.scene.layouts.diff_2_hor", "Diff2Hor") ---@type Diff2Hor|LazyModule
local Diff2Ver = lazy.access("diffview.scene.layouts.diff_2_ver", "Diff2Ver") ---@type Diff2Ver|LazyModule
local Diff3Hor = lazy.access("diffview.scene.layouts.diff_3_hor", "Diff3Hor") ---@type Diff3Hor|LazyModule
local Diff3Ver = lazy.access("diffview.scene.layouts.diff_3_ver", "Diff3Ver") ---@type Diff3Ver|LazyModule
local Diff4Mixed = lazy.access("diffview.scene.layouts.diff_4_mixed", "Diff4Mixed") ---@type Diff4Mixed|LazyModule
local EventEmitter = lazy.access("diffview.events", "EventEmitter") ---@type EventEmitter|LazyModule
local File = lazy.access("diffview.vcs.file", "File") ---@type vcs.File|LazyModule
local Signal = lazy.access("diffview.control", "Signal") ---@type Signal|LazyModule
local config = lazy.require("diffview.config") ---@module "diffview.config"
local utils = lazy.require("diffview.utils") ---@module "diffview.utils"
local ViewShell = require("diffview.ui.view_shell")

local ctx = require("diffview.runtime.context") ---@module "diffview.runtime.context"
local api = vim.api
local M = {}

-- Boolean diffopt flags that can be toggled.
local diffopt_bool_flags = {
  "indent-heuristic",
  "iwhite",
  "iwhiteall",
  "iwhiteeol",
  "iblank",
  "icase",
}

---Apply configured diffopt overrides, saving the original value on the view.
---Split the current global diffopt into its comma-separated flags.
---@return string[]
local function get_diffopt_parts()
  return vim.split(vim.o.diffopt, ",", { trimempty = true })
end

---Write parts back to the global diffopt option.
---@param parts string[]
local function set_diffopt_parts(parts)
  vim.o.diffopt = table.concat(parts, ",")
end

---@param parts string[]
---@param prefix string # Remove entries beginning with this prefix (e.g., "algorithm:").
local function strip_prefix(parts, prefix)
  for i = #parts, 1, -1 do
    if parts[i]:sub(1, #prefix) == prefix then
      table.remove(parts, i)
    end
  end
end

---@param parts string[]
---@param value string # Remove entries that exactly match this value (e.g., "iwhite").
local function strip_exact(parts, value)
  for i = #parts, 1, -1 do
    if parts[i] == value then
      table.remove(parts, i)
    end
  end
end

---@param view View
local function apply_diffopt(view)
  local conf = config.get_config().diffopt
  if not conf or vim.tbl_isempty(conf) then
    return
  end

  if not view._saved_diffopt then
    view._saved_diffopt = get_diffopt_parts()
  end

  local parts = get_diffopt_parts()

  if conf.algorithm then
    strip_prefix(parts, "algorithm:")
    parts[#parts + 1] = "algorithm:" .. conf.algorithm
  end

  if conf.context ~= nil then
    strip_prefix(parts, "context:")
    parts[#parts + 1] = "context:" .. conf.context
  end

  if conf.linematch ~= nil then
    strip_prefix(parts, "linematch:")
    parts[#parts + 1] = "linematch:" .. conf.linematch
  end

  for _, flag in ipairs(diffopt_bool_flags) do
    -- Convert config key (underscore-separated) to diffopt flag (hyphenated).
    local key = flag:gsub("-", "_")
    if conf[key] ~= nil then
      strip_exact(parts, flag)
      if conf[key] then
        parts[#parts + 1] = flag
      end
    end
  end

  set_diffopt_parts(parts)
end

---Restore the original diffopt value from the view.
---@param view View
local function restore_diffopt(view)
  if view._saved_diffopt then
    set_diffopt_parts(view._saved_diffopt)
    view._saved_diffopt = nil
  end
end

---@enum LayoutMode
local LayoutMode = {
  HORIZONTAL = 1,
  VERTICAL = 2,
}
utils.add_reverse_lookup(LayoutMode)

---@class diffview.View.CloseOpts
---@field force? boolean

---@class View
---@field class View
---@field super_class? View
---@field tabpage integer
---@field emitter EventEmitter
---@field default_layout Layout (class)
---@field ready boolean
---@field closing Signal
---@field _saved_diffopt string[]? Per-view saved diffopt value before overrides.
---@field _global_callbacks table<any, function> # Callbacks registered on the global emitter, keyed by event.
---@field shell diffview.ViewShell
---@field effects diffview.EffectScope
local View = { __name = "View" }
View.__index = View
setmetatable(View, {
  __call = function(_, ...)
    local view = setmetatable({ class = View }, View)
    view:init(...)
    return view
  end,
})

---@param target table
---@return boolean
function View:instanceof(target)
  local class = self.class
  while class do
    if class == target then
      return true
    end
    class = class.super_class
  end
  return false
end

---@param value any
---@return boolean
function View:ancestorof(value)
  return type(value) == "table" and type(value.instanceof) == "function" and value:instanceof(self)
end

---@return string
function View:name()
  return self.__name or "View"
end

---@diagnostic disable unused-local

---@abstract
function View:init_layout()
  error("Abstract method 'View:init_layout' must be implemented", 2)
end

---@abstract
function View:post_open()
  error("Abstract method 'View:post_open' must be implemented", 2)
end

---@diagnostic enable unused-local

---View constructor
function View:init(opt)
  opt = opt or {}
  self.emitter = opt.emitter or EventEmitter()
  self.default_layout = opt.default_layout or View.get_default_layout()
  self.ready = utils.sate(opt.ready, false)
  self.closing = utils.sate(opt.closing, Signal())
  self._global_callbacks = {}
  self.shell = ViewShell.new(self)
  self.effects = self.shell.effects

  local function wrap_event(event)
    local cb = function(_, view, ...)
      -- Most lifecycle events carry their view explicitly. Avoid loading lib
      -- (and its global integrations) unless an unscoped event actually needs
      -- current-view resolution.
      if view == self or (not view and require("diffview.lib").get_current_view() == self) then
        self.emitter:emit(event, view, ...)
      end
    end

    self._global_callbacks[event] = cb
    ctx.emitter:on(event, cb)
  end

  wrap_event("view_closed")

  -- Apply/restore diffopt overrides on tab enter/leave.
  self.emitter:on("tab_enter", function()
    apply_diffopt(self)
  end)
  self.emitter:on("tab_leave", function()
    restore_diffopt(self)
  end)
end

function View:open()
  self.shell:begin_loading()
  -- Auto-register so that integrating plugins (e.g., Neogit) don't need to
  -- reach into diffview.lib to call add_view().
  require("diffview.lib").add_view(self)

  -- :h nvim_open_tabpage(bufnr, enter, opts)
  --   bufnr  = 0      → use the current buffer in the new tab
  --   enter  = true   → make the new tabpage current immediately
  --   opts   = {}     → no extra options required
  --
  -- Prefer this over `vim.cmd("tab split")` because:
  --   • nvim_open_tabpage does not fire BufEnter for the existing tab's
  --     buffers, avoiding unwanted autocmd side-effects in integrating plugins.
  --   • The return value is the tabpage handle, directly usable with
  --     other nvim_* API calls.
  self.tabpage = api.nvim_open_tabpage(0, true, {})
  self:init_layout()
  self:post_open()
  apply_diffopt(self)
  ctx.emitter:emit("view_opened", self)
  ctx.emitter:emit("view_enter", self)
end

---@param opts? diffview.View.CloseOpts # Forwarded to subclass overrides; ignored at the base level.
---@return boolean? closed # `false` if a subclass aborted the close.
---@diagnostic disable-next-line: unused-local
function View:close(opts)
  self.shell:begin_close()
  self.closing:send()

  if self.tabpage and api.nvim_tabpage_is_valid(self.tabpage) then
    ctx.emitter:emit("view_leave", self)
    restore_diffopt(self)

    if #api.nvim_list_tabpages() == 1 then
      vim.cmd("tabnew")
    end

    local pagenr = api.nvim_tabpage_get_number(self.tabpage)
    local ok, err = pcall(api.nvim_command, "tabclose " .. pagenr)
    if not ok and type(err) == "string" and err:match("E445") then
      vim.cmd("tabclose! " .. pagenr)
    end
  end

  ctx.emitter:emit("view_closed", self)

  -- Unsubscribe all global listeners to prevent leaked references.
  for event, cb in pairs(self._global_callbacks) do
    ctx.emitter:off(cb, event)
  end

  self._global_callbacks = {}
  self.emitter:clear()
  self.shell:close()
end

function View:is_cur_tabpage()
  return self.tabpage == api.nvim_get_current_tabpage()
end

---@return boolean
local function prefer_horizontal()
  local diffopt = vim.opt.diffopt --[[@as vim.Option]]
  return vim.tbl_contains(diffopt:get() --[[@as string[] ]], "vertical")
end

---@return Diff1
function View.get_default_diff1()
  return Diff1.__get()
end

---@return Diff2
function View.get_default_diff2()
  if prefer_horizontal() then
    return Diff2Hor.__get()
  else
    return Diff2Ver.__get()
  end
end

---@return Diff3
function View.get_default_diff3()
  if prefer_horizontal() then
    return Diff3Hor.__get()
  else
    return Diff3Ver.__get()
  end
end

---@return Diff4
function View.get_default_diff4()
  return Diff4Mixed.__get()
end

---@return LayoutName|-1
function View.get_default_layout_name()
  return config.get_config().view.default.layout
end

---@return Layout # (class) The default layout class.
function View.get_default_layout()
  local name = View.get_default_layout_name()

  if name == -1 then
    return View.get_default_diff2()
  end

  return config.name_to_layout(name --[[@as string ]])
end

---@return Layout
function View.get_default_merge_layout()
  local name = config.get_config().view.merge_tool.layout

  if name == -1 then
    return View.get_default_diff3()
  end

  return config.name_to_layout(name --[[@as string ]])
end

---@return Diff2
function View.get_temp_layout()
  local layout_class = View.get_default_layout()
  return layout_class({
    a = File.NULL_FILE,
    b = File.NULL_FILE,
  })
end

M.LayoutMode = LayoutMode
M.View = View
M._test = {
  apply_diffopt = apply_diffopt,
  restore_diffopt = restore_diffopt,
}

return M
