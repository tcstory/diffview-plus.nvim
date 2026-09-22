local Rev = require("diffview.vcs.rev").Rev
local RevType = require("diffview.vcs.rev").RevType

local M = {}

---@class NullRev : Rev
local NullRev = {}
NullRev.__index = NullRev
NullRev.__tostring = Rev.__tostring
setmetatable(NullRev, {
  __index = Rev,
  __call = function(_, ...)
    local rev = setmetatable({}, NullRev)
    rev:init(...)
    return rev
  end,
})

---NullRev constructor
---@param rev_type RevType
---@param revision? string|number
---@param track_head? boolean
function NullRev:init(rev_type, revision, track_head)
  Rev.init(self, rev_type, revision, track_head)
end

---@param rev_from NullRev|string
---@param rev_to? NullRev|string
---@return string?
function NullRev.to_range(rev_from, rev_to)
  return nil
end

---@param name string
---@param adapter? VCSAdapter
---@return Rev?
function NullRev.from_name(name, adapter)
  return nil
end

---@param adapter VCSAdapter
---@return Rev?
function NullRev.earliest_commit(adapter)
  return nil
end

---@return Rev
function NullRev.new_null_tree()
  return NullRev(RevType.LOCAL)
end

---@param adapter VCSAdapter
---@return boolean?
function NullRev:is_head(adapter)
  return false
end

---@param abbrev_len? integer
---@return string
function NullRev:object_name(abbrev_len)
  if self.type == RevType.LOCAL then
    return "LOCAL"
  end
  return "NULL"
end

M.NullRev = NullRev
return M
