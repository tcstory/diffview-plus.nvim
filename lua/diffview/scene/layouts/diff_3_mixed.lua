local async = require("diffview.async")
local Diff3 = require("diffview.scene.layouts.diff_3").Diff3

local await = async.await

local M = {}

---@class Diff3Mixed : Diff3
local Diff3Mixed = {}
Diff3Mixed.__index = Diff3Mixed
Diff3Mixed.super_class = Diff3
setmetatable(Diff3Mixed, {
  __index = Diff3,
  __call = function(_, ...)
    local layout = setmetatable({ class = Diff3Mixed }, Diff3Mixed)
    layout:init(...)
    return layout
  end,
})

Diff3Mixed.name = "diff3_mixed"

function Diff3Mixed:init(opt)
  Diff3.init(self, opt)
end

---@override
---@param self Diff3Mixed
---@param pivot integer?
Diff3Mixed.create = async.void(function(self, pivot)
  await(self:create_wins(pivot, {
    { "b", "belowright sp" },
    { "a", "aboveleft vsp" },
    { "c", "aboveleft vsp" },
  }, { "a", "b", "c" }))
end)

M.Diff3Mixed = Diff3Mixed
return M
