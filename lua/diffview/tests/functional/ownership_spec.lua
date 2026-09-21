local BufferLease = require("diffview.ui.buffer_lease")
local LayoutSpec = require("diffview.ui.layout_spec")
local ViewShell = require("diffview.ui.view_shell")
local WindowLease = require("diffview.ui.window_lease")

local api = vim.api

describe("Phase 5 ownership primitives", function()
  it("ViewShell gates work while loading and releases owned resources", function()
    local owner = { ready = false }
    local shell = ViewShell.new(owner)
    local released = false
    shell:own({
      release = function()
        released = true
      end,
    })
    shell:begin_loading()
    local available, reason = shell:can_execute()
    assert.is_false(available)
    assert.equals("View is loading", reason)
    owner.ready = true
    assert.is_true(shell:can_execute())
    shell:close()
    assert.is_true(released)
    assert.is_false(shell:can_execute())
  end)

  it("BufferLease restores pre-existing options and keymaps exactly", function()
    local bufnr = api.nvim_create_buf(false, true)
    vim.bo[bufnr].modifiable = true
    vim.keymap.set("n", "gq", "<Cmd>let g:lease_original = 1<CR>", {
      buffer = bufnr,
      desc = "original",
    })
    local lease = BufferLease.new(bufnr)
    lease:set_option("modifiable", false)
    lease:set_keymap("n", "gq", "<Cmd>let g:lease_temporary = 1<CR>")
    assert.is_false(vim.bo[bufnr].modifiable)
    lease:release()
    assert.is_true(vim.bo[bufnr].modifiable)
    local restored
    for _, km in ipairs(api.nvim_buf_get_keymap(bufnr, "n")) do
      if km.lhs == "gq" then
        restored = km
      end
    end
    assert.equals("<Cmd>let g:lease_original = 1<CR>", restored.rhs)
    assert.equals("original", restored.desc)
    api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("BufferLease preserves an already-disabled diagnostic state", function()
    local bufnr = api.nvim_create_buf(false, true)
    vim.diagnostic.enable(false, { bufnr = bufnr })
    local lease = BufferLease.new(bufnr)
    lease:disable_diagnostics()
    lease:release()
    assert.is_false(vim.diagnostic.is_enabled({ bufnr = bufnr }))
    vim.diagnostic.enable(true, { bufnr = bufnr })
    api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("WindowLease round-trips cursor, viewport, folds and local options", function()
    local winid = api.nvim_get_current_win()
    local bufnr = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(bufnr, 0, -1, false, { "one", "two", "three", "four" })
    api.nvim_win_set_buf(winid, bufnr)
    vim.wo[winid].foldmethod = "manual"
    api.nvim_win_set_cursor(winid, { 3, 0 })
    local lease = WindowLease.new(winid)
    local saved = lease:capture()
    api.nvim_win_set_cursor(winid, { 1, 0 })
    vim.wo[winid].foldmethod = "indent"
    assert.is_true(lease:restore(saved))
    assert.same({ 3, 0 }, api.nvim_win_get_cursor(winid))
    assert.equals("manual", vim.wo[winid].foldmethod)
    api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("LayoutSpec validates slots and deep-copies caller data", function()
    local slots = { { symbol = "a", command = "leftabove vsplit" } }
    local spec = LayoutSpec.new("single", slots, { "a" }, { min_width = 20 })
    slots[1].symbol = "changed"
    assert.equals("a", spec.slots[1].symbol)
    assert.has_error(function()
      LayoutSpec.new("broken", slots, { "missing" })
    end)
  end)
end)
