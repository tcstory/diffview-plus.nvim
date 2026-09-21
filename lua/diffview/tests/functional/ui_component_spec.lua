local component = require("diffview.ui.component")
local router = require("diffview.ui.router")

describe("UI components and router", function()
  after_each(function()
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
end)
