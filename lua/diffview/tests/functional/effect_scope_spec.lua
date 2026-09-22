local EffectScope = require("diffview.runtime.effect_scope")

describe("diffview.runtime.effect_scope", function()
  it("closes resources in reverse order and only once", function()
    local calls = {}
    local scope = EffectScope.new()
    scope:own(function()
      calls[#calls + 1] = "first"
    end)
    scope:own(function()
      calls[#calls + 1] = "second"
    end)

    assert.same({}, scope:close("done"))
    assert.same({ "second", "first" }, calls)
    scope:close("again")
    assert.same({ "second", "first" }, calls)
  end)

  it("closes children before parent resources", function()
    local calls = {}
    local parent = EffectScope.new()
    parent:own(function()
      calls[#calls + 1] = "parent"
    end)
    parent:child():own(function()
      calls[#calls + 1] = "child"
    end)

    parent:close()
    assert.same({ "child", "parent" }, calls)
  end)

  it("supports explicit cleanup, disown, and immediate late ownership", function()
    local calls = {}
    local scope = EffectScope.new()
    local kept = {}
    scope:own(kept, function()
      calls[#calls + 1] = "kept"
    end)
    assert.is_true(scope:disown(kept))
    scope:close("closed")
    scope:own("late", function(value, reason)
      calls[#calls + 1] = value .. ":" .. reason
    end)
    assert.same({ "late:closed" }, calls)
  end)

  it("notifies cancellation and continues after cleanup errors", function()
    local calls = {}
    local scope = EffectScope.new()
    scope:listen(function(_, reason)
      calls[#calls + 1] = reason
    end)
    scope:own(function()
      calls[#calls + 1] = "after-error"
    end)
    scope:own(function()
      error("cleanup failed")
    end)

    local errors = scope:close("cancelled")
    assert.is_true(scope:check())
    assert.same({ "cancelled", "after-error" }, calls)
    assert.equals(1, #errors)
    assert.matches("cleanup failed", errors[1])
  end)
end)
