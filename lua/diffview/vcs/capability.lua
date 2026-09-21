---Stable adapter capabilities used by UI and command surfaces.
---Adapters declare support; consumers never inspect adapter class identity.

---@enum vcs.Capability
local Capability = {
  STATUS = "status",
  HISTORY = "history",
  MERGE_CONTEXT = "merge_context",
  TRANSACTIONAL_MERGE = "transactional_merge",
  STAGE = "stage",
  RESTORE = "restore",
  PIN_LOCAL = "pin_local",
  INDEX_WATCH = "index_watch",
  REVISION = "revision",
  COMPLETION = "completion",
}

---@param ... vcs.Capability
---@return table<vcs.Capability, true>
local function set(...)
  local capabilities = {}
  for i = 1, select("#", ...) do
    capabilities[select(i, ...)] = true
  end
  return capabilities
end

return { Capability = Capability, set = set }
