local lazy = require("diffview.lazy")
local ctx = require("diffview.runtime.context")

if ctx.bootstrap_done then
  return ctx.bootstrap_ok
end

local EventEmitter = lazy.access("diffview.events", "EventEmitter") ---@type EventEmitter|LazyModule
local Logger = lazy.access("diffview.logger", "Logger") ---@type Logger|LazyModule
local config = lazy.require("diffview.config") ---@module "diffview.config"
local diffview = lazy.require("diffview") ---@module "diffview"
local utils = lazy.require("diffview.utils") ---@module "diffview.utils"

local function err(msg)
  msg = msg:gsub("'", "''")
  vim.cmd("echohl Error")
  vim.cmd(string.format("echom '[diffview+] %s'", msg))
  vim.cmd("echohl NONE")
end

ctx.bootstrap_done = true
ctx.bootstrap_ok = false

if vim.fn.has("nvim-0.12") ~= 1 then
  err("Minimum required version is Neovim 0.12.0! Cannot continue.")
  return false
end

local logger = Logger()
local emitter = EventEmitter()
local state = {}
local debug_level = tonumber(vim.env.DEBUG_DIFFVIEW) or 0

emitter:on_any(function(e, args)
  diffview.nore_emit(e.id, utils.tbl_unpack(args))
  config.user_emitter:nore_emit(e.id, utils.tbl_unpack(args))
end)

ctx.init({
  logger = logger,
  emitter = emitter,
  debug_level = debug_level,
  state = state,
})
ctx.bootstrap_ok = true

return true
