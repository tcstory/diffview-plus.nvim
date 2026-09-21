---Compatibility facade for domain action modules.
---
---New integrations should use `require("diffview.api").actions` and stable
---action IDs.  Named functions remain available while callers migrate.

local M = require("diffview.actions.impl")
local register = require("diffview.actions.register")(M)

for _, domain in ipairs({ "navigation", "file", "history", "diff", "merge", "layout", "view" }) do
  require("diffview.actions." .. domain)(M, register)
end

return M
