local renderer = require("diffview.renderer")

describe("renderer patching", function()
  it("updates one row rather than redrawing a 1000-line panel", function()
    local buffer = vim.api.nvim_create_buf(false, true)
    local data = renderer.RenderData("diffview-renderer-patch-test")
    for index = 1, 1000 do
      data.lines[index] = "line " .. index
    end
    renderer.render(buffer, data)
    data.lines[500] = "changed"
    renderer.render(buffer, data)

    assert.equals(1, data.last_patch.lines_written)
    assert.equals(499, data.last_patch.start_row)
    assert.equals("changed", vim.api.nvim_buf_get_lines(buffer, 499, 500, false)[1])
    assert.is_true(renderer.last_draw_time < 100)
    vim.api.nvim_buf_delete(buffer, { force = true })
  end)
end)
