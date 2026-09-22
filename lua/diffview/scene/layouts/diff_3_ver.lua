local async = require("diffview.async")
local Diff3 = require("diffview.scene.layouts.diff_3").Diff3

local await = async.await

local M = {}

---@class Diff3Ver : Diff3
local Diff3Ver = {}
Diff3Ver.__index = Diff3Ver
Diff3Ver.super_class = Diff3
setmetatable(Diff3Ver, {
  __index = Diff3,
  __call = function(_, ...)
    local layout = setmetatable({ class = Diff3Ver }, Diff3Ver)
    layout:init(...)
    return layout
  end,
})

Diff3Ver.name = "diff3_vertical"

function Diff3Ver:init(opt)
  Diff3.init(self, opt)
end

---@override
---@param self Diff3Ver
---@param pivot integer?
Diff3Ver.create = async.void(function(self, pivot)
  await(self:create_wins(pivot, {
    { "a", "aboveleft sp" },
    { "b", "aboveleft sp" },
    { "c", "aboveleft sp" },
  }, { "a", "b", "c" }))
end)

M.Diff3Ver = Diff3Ver
return M
