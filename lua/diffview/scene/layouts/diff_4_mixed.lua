local async = require("diffview.async")
local Diff4 = require("diffview.scene.layouts.diff_4").Diff4

local await = async.await

local M = {}

---@class Diff4Mixed : Diff4
local Diff4Mixed = {}
Diff4Mixed.__index = Diff4Mixed
Diff4Mixed.super_class = Diff4
setmetatable(Diff4Mixed, {
  __index = Diff4,
  __call = function(_, ...)
    local layout = setmetatable({ class = Diff4Mixed }, Diff4Mixed)
    layout:init(...)
    return layout
  end,
})

Diff4Mixed.name = "diff4_mixed"

function Diff4Mixed:init(opt)
  Diff4.init(self, opt)
end

---@override
---@param self Diff4Mixed
---@param pivot integer?
Diff4Mixed.create = async.void(function(self, pivot)
  await(self:create_wins(pivot, {
    { "b", "belowright sp" },
    { "a", "aboveleft vsp" },
    { "d", "aboveleft vsp" },
    { "c", "aboveleft vsp" },
  }, { "a", "b", "c", "d" }))
end)

M.Diff4Mixed = Diff4Mixed
return M
