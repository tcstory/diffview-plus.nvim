---Viewport-only decorations. Decorations must be reconstructable on every
---`on_range` call because ephemeral extmarks are never persisted.

local api = vim.api
local M = {}

---@param name string
---@param build fun(bufnr: integer, first_row: integer, last_row: integer): table[]
---@return { namespace: integer, stop: fun() }
function M.start(name, build)
  local namespace = api.nvim_create_namespace(name)
  api.nvim_set_decoration_provider(namespace, {
    on_range = function(_, _, bufnr, first_row, last_row)
      for _, mark in ipairs(build(bufnr, first_row, last_row) or {}) do
        local row = assert(mark.row, "viewport decoration requires row")
        if row >= first_row and row < last_row then
          local opts = vim.tbl_extend("force", mark.opts or {}, { ephemeral = true })
          api.nvim_buf_set_extmark(bufnr, namespace, row, mark.col or 0, opts)
        end
      end
    end,
  })
  return {
    namespace = namespace,
    stop = function()
      api.nvim_set_decoration_provider(namespace, {})
    end,
  }
end

return M
