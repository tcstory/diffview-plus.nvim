local lazy = require("diffview.lazy")
local utils = require("diffview.utils")
local Commit = require("diffview.vcs.commit").Commit

local M = {}

---@class HgCommit : Commit
local HgCommit = {}
HgCommit.__index = HgCommit
setmetatable(HgCommit, {
  __index = Commit,
  __call = function(_, ...)
    local commit = setmetatable({}, HgCommit)
    commit:init(...)
    return commit
  end,
})

function HgCommit:init(opt)
  Commit.init(self, opt)

  if opt.time_offset then
    self.time_offset = HgCommit.parse_time_offset(opt.time_offset)
    self.time = self.time - self.time_offset
  else
    self.time_offset = 0
  end

  self.iso_date = Commit.time_to_iso(self.time, self.time_offset)
end

---@param iso_date string?
function HgCommit.parse_time_offset(iso_date)
  if not iso_date or iso_date == "" then
    return 0
  end

  local sign, offset = vim.trim(iso_date):match("([+-])(%d+)")

  offset = tonumber(offset)

  if sign == "-" then
    offset = -offset
  end

  return offset
end

M.HgCommit = HgCommit
return M
