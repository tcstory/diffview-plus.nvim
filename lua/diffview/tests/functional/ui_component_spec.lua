local component = require("diffview.ui.component")
local router = require("diffview.ui.router")

describe("UI components and router", function()
  local original_getmousepos

  before_each(function()
    original_getmousepos = vim.fn.getmousepos
  end)

  after_each(function()
    vim.fn.getmousepos = original_getmousepos
    router._reset()
  end)

  it("creates immutable component values", function()
    local value = component.new({
      identity = "sample",
      text = { { text = "文" }, { text = "é" } },
      action = "view.close",
    })
    assert.equals("文é", component.text(value))
    assert.equals(3, component.width(value))
    assert.has_error(function()
      value.identity = "changed"
    end)
  end)

  it("preserves frozen children when components are nested", function()
    local child =
      component.new({ identity = "child", text = "Refresh", action = "file.refresh_files" })
    local root = component.new({ identity = "root", children = { child } })
    local nested = component.children(root)[1]

    assert.equals("Refresh", component.text(nested))
    assert.equals("file.refresh_files", nested.action)
  end)

  it("calculates hit zones for narrow, wide, combining and RTL text", function()
    local spans = router.segment_spans({
      { text = "x" },
      { text = "界" },
      { text = "é" },
      { text = "שלום" },
    })
    assert.same({ 1, 1 }, { spans[1].start_col, spans[1].end_col })
    assert.same({ 2, 3 }, { spans[2].start_col, spans[2].end_col })
    assert.same({ 4, 4 }, { spans[3].start_col, spans[3].end_col })
    assert.same({ 5, 8 }, { spans[4].start_col, spans[4].end_col })
  end)

  it("removes every route owned by a destroyed UI", function()
    local owner = {}
    router.register({ owner = owner, handler = function() end })
    router.register({ owner = owner, handler = function() end })
    assert.equals(2, router.size())
    router.unregister_owner(owner)
    assert.equals(0, router.size())
  end)

  it("routes the first click to a control in a different buffer", function()
    local target_bufnr = vim.api.nvim_get_current_buf()
    local target_winid = vim.api.nvim_get_current_win()
    local mapped_bufnr = vim.api.nvim_create_buf(false, true)
    local mapped_winid = vim.api.nvim_open_win(mapped_bufnr, true, {
      relative = "editor",
      row = 1,
      col = 1,
      width = 10,
      height = 2,
    })
    local invoked = 0
    router.register({
      bufnr = target_bufnr,
      line = 1,
      start_col = 1,
      end_col = 8,
      handler = function()
        invoked = invoked + 1
      end,
    })
    vim.fn.getmousepos = function()
      return { winid = target_winid, line = 1, wincol = 1, screenrow = 1 }
    end

    local result = router.callback("mouse", mapped_bufnr)()

    assert.equals("", result)
    assert.equals(1, invoked)
    assert.equals(target_winid, vim.api.nvim_get_current_win())
    assert.equals(1, vim.api.nvim_win_get_cursor(target_winid)[1])
    vim.api.nvim_win_close(mapped_winid, true)
    vim.api.nvim_buf_delete(mapped_bufnr, { force = true })
  end)

  it("returns unhandled clicks to Neovim for native focus behaviour", function()
    local target_winid = vim.api.nvim_get_current_win()
    local mapped_bufnr = vim.api.nvim_create_buf(false, true)
    vim.fn.getmousepos = function()
      return { winid = target_winid, line = 1, wincol = 1, screenrow = 1 }
    end

    assert.equals("<LeftMouse>", router.callback("mouse", mapped_bufnr)())
    vim.api.nvim_buf_delete(mapped_bufnr, { force = true })
  end)
end)
