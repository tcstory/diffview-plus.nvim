---Built-in action registration and direct action implementations.
---
---Public integrations should use `require("diffview.api").actions` and stable
---action IDs. Internal listeners may call the implementation table when they
---are adapting editor events that are not action surfaces.

local M = require("diffview.actions.impl")
local register = require("diffview.actions.register")(M)

for _, domain in ipairs({ "navigation", "file", "history", "diff", "merge", "layout", "view" }) do
  require("diffview.actions." .. domain)(M, register)
end

return M
