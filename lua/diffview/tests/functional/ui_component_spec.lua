local component = require("diffview.ui.component")
local router = require("diffview.ui.router")
local actions = require("diffview.runtime.action_registry")

describe("UI components and router", function()
  local original_getmousepos
  local original_feedkeys
  local original_execute

  before_each(function()
    original_getmousepos = vim.fn.getmousepos
    original_feedkeys = vim.api.nvim_feedkeys
    original_execute = actions.execute
  end)

  after_each(function()
    vim.fn.getmousepos = original_getmousepos
    vim.api.nvim_feedkeys = original_feedkeys
    actions.execute = original_execute
    local mode = vim.api.nvim_get_mode().mode
    if mode == "v" or mode == "V" or mode == "\22" then
      vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
    end
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

    assert.is_nil(result)
    assert.equals(1, invoked)
    assert.equals(target_winid, vim.api.nvim_get_current_win())
    assert.equals(1, vim.api.nvim_win_get_cursor(target_winid)[1])
    vim.api.nvim_win_close(mapped_winid, true)
    vim.api.nvim_buf_delete(mapped_bufnr, { force = true })
  end)

  it("leaves Visual mode before running a routed mouse action", function()
    local target_bufnr = vim.api.nvim_get_current_buf()
    local target_winid = vim.api.nvim_get_current_win()
    local mode_during_action
    router.register({
      bufnr = target_bufnr,
      line = 1,
      handler = function()
        mode_during_action = vim.api.nvim_get_mode().mode
      end,
    })
    vim.fn.getmousepos = function()
      return { winid = target_winid, line = 1, wincol = 1, screenrow = 1 }
    end
    vim.api.nvim_feedkeys("v", "nx", false)
    assert.equals("v", vim.api.nvim_get_mode().mode)

    router.callback("mouse", target_bufnr)()

    assert.equals("n", mode_during_action)
    assert.equals("n", vim.api.nvim_get_mode().mode)
  end)

  it("replays unhandled clicks without remapping for native focus behaviour", function()
    local target_winid = vim.api.nvim_get_current_win()
    local mapped_bufnr = vim.api.nvim_create_buf(false, true)
    local replayed
    vim.api.nvim_feedkeys = function(keys, mode, escape_csi)
      replayed = { keys, mode, escape_csi }
    end
    vim.fn.getmousepos = function()
      return { winid = target_winid, line = 1, wincol = 1, screenrow = 1 }
    end

    assert.is_nil(router.callback("mouse", mapped_bufnr)())
    assert.same({ vim.keycode("<LeftMouse>"), "n", false }, replayed)
    vim.api.nvim_buf_delete(mapped_bufnr, { force = true })
  end)

  it("passes winbar clicks to Neovim instead of running a panel fallback", function()
    local target_bufnr = vim.api.nvim_get_current_buf()
    local target_winid = vim.api.nvim_get_current_win()
    local invoked = 0
    local replayed
    actions.execute = function()
      invoked = invoked + 1
    end
    vim.api.nvim_feedkeys = function(keys, mode, escape_csi)
      replayed = { keys, mode, escape_csi }
    end
    vim.fn.getmousepos = function()
      return { winid = target_winid, line = 0, wincol = 3, screenrow = 1 }
    end

    router.callback("mouse", target_bufnr, "test.select_entry")()

    assert.equals(0, invoked)
    assert.same({ vim.keycode("<LeftMouse>"), "n", false }, replayed)
  end)

  it("runs winbar actions once for a left single-click", function()
    local invoked = 0
    local id = router.register({
      handler = function()
        invoked = invoked + 1
      end,
    })

    _G.DiffviewUIRouter(id, 2, "l", "    ")
    _G.DiffviewUIRouter(id, 1, "r", "    ")
    assert.equals(0, invoked)

    _G.DiffviewUIRouter(id, 1, "l", "    ")
    assert.equals(1, invoked)
  end)

  it("uses the target buffer fallback on the first cross-buffer click", function()
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
    actions.execute = function(action)
      assert.equals("test.select_entry", action)
      invoked = invoked + 1
    end
    router.callback("mouse", target_bufnr, "test.select_entry")
    vim.fn.getmousepos = function()
      return { winid = target_winid, line = 1, wincol = 1, screenrow = 1 }
    end

    router.callback("mouse", mapped_bufnr)()

    assert.equals(1, invoked)
    assert.equals(target_winid, vim.api.nvim_get_current_win())
    vim.api.nvim_win_close(mapped_winid, true)
    vim.api.nvim_buf_delete(mapped_bufnr, { force = true })
  end)
end)
