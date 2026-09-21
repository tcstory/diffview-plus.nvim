local viewport = require("diffview.ui.viewport_decorations")

describe("viewport decorations", function()
  it("registers a reconstructable on_range provider", function()
    local original = vim.api.nvim_set_decoration_provider
    local captured
    vim.api.nvim_set_decoration_provider = function(_, provider)
      captured = provider
    end
    local handle = viewport.start("diffview-viewport-test", function()
      return {}
    end)
    assert.is_function(captured.on_range)
    handle.stop()
    assert.same({}, captured)
    vim.api.nvim_set_decoration_provider = original
  end)
end)
