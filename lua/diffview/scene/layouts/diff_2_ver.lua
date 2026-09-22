local async = require("diffview.async")
local Diff2 = require("diffview.scene.layouts.diff_2").Diff2

local await = async.await

local M = {}

---@class Diff2Ver : Diff2
local Diff2Ver = {}
Diff2Ver.__index = Diff2Ver
Diff2Ver.super_class = Diff2
setmetatable(Diff2Ver, {
  __index = Diff2,
  __call = function(_, ...)
    local layout = setmetatable({ class = Diff2Ver }, Diff2Ver)
    layout:init(...)
    return layout
  end,
})

Diff2Ver.name = "diff2_vertical"

---@param opt Diff2.init.Opt
function Diff2Ver:init(opt)
  Diff2.init(self, opt)
end

---@override
---@param self Diff2Ver
---@param pivot integer?
Diff2Ver.create = async.void(function(self, pivot)
  await(self:create_wins(pivot, {
    { "a", "aboveleft sp" },
    { "b", "aboveleft sp" },
  }, { "a", "b" }))
end)

M.Diff2Ver = Diff2Ver
return M
