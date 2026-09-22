local async = require("diffview.async")
local Diff3 = require("diffview.scene.layouts.diff_3").Diff3

local await = async.await

local M = {}

---@class Diff3Hor : Diff3
local Diff3Hor = {}
Diff3Hor.__index = Diff3Hor
Diff3Hor.super_class = Diff3
setmetatable(Diff3Hor, {
  __index = Diff3,
  __call = function(_, ...)
    local layout = setmetatable({ class = Diff3Hor }, Diff3Hor)
    layout:init(...)
    return layout
  end,
})

Diff3Hor.name = "diff3_horizontal"

function Diff3Hor:init(opt)
  Diff3.init(self, opt)
end

---@override
---@param self Diff3Hor
---@param pivot integer?
Diff3Hor.create = async.void(function(self, pivot)
  await(self:create_wins(pivot, {
    { "a", "aboveleft vsp" },
    { "b", "aboveleft vsp" },
    { "c", "aboveleft vsp" },
  }, { "a", "b", "c" }))
end)

M.Diff3Hor = Diff3Hor
return M
