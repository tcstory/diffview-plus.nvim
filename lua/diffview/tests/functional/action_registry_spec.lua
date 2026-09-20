--- tests/functional/action_registry_spec.lua
---
--- Unit tests for lua/diffview/runtime/action_registry.lua.
--- All tests are pure Lua (no Neovim API needed at the test level).

local registry = require("diffview.runtime.action_registry")

describe("diffview.runtime.action_registry", function()
  -- Reset registry state between tests so registrations don't bleed across.
  before_each(function()
    registry._reset()
  end)

  describe("register / get", function()
    it("stores a registered action by id", function()
      registry.register({
        id       = "test.foo",
        label    = "Foo",
        desc     = "Does foo",
        category = registry.ActionCategory.DIFF,
        execute  = function() end,
      })
      local spec = registry.get("test.foo")
      assert.is_not_nil(spec)
      assert.are.equal("test.foo", spec.id)
      assert.are.equal("Foo", spec.label)
    end)

    it("returns nil for an unregistered id", function()
      assert.is_nil(registry.get("nonexistent.action"))
    end)

    it("raises on duplicate id", function()
      local spec = { id = "test.dup", label = "", desc = "", category = "diff", execute = function() end }
      registry.register(spec)
      assert.has_error(function() registry.register(spec) end, nil)
    end)

    it("raises when id is empty string", function()
      assert.has_error(function()
        registry.register({ id = "", label = "", desc = "", category = "diff", execute = function() end })
      end)
    end)

    it("raises when execute is not a function", function()
      assert.has_error(function()
        registry.register({ id = "test.bad", label = "", desc = "", category = "diff", execute = "oops" })
      end)
    end)
  end)

  describe("register_all", function()
    it("registers multiple actions in one call", function()
      registry.register_all({
        { id = "a.one", label = "One", desc = "", category = "diff", execute = function() end },
        { id = "a.two", label = "Two", desc = "", category = "history", execute = function() end },
      })
      assert.is_not_nil(registry.get("a.one"))
      assert.is_not_nil(registry.get("a.two"))
    end)
  end)

  describe("execute", function()
    it("calls execute with the provided arguments", function()
      local called_with = {}
      registry.register({
        id       = "test.exec",
        label    = "",
        desc     = "",
        category = "diff",
        execute  = function(a, b) called_with = { a, b } end,
      })
      registry.execute("test.exec", nil, "hello", 42)
      assert.are.same({ "hello", 42 }, called_with)
    end)

    it("raises on unknown action id", function()
      assert.has_error(function() registry.execute("no.such.action") end)
    end)

    it("is a no-op when available() returns false", function()
      local called = false
      registry.register({
        id        = "test.unavail",
        label     = "",
        desc      = "",
        category  = "diff",
        available = function(_view) return false end,
        execute   = function() called = true end,
      })
      registry.execute("test.unavail", nil)
      assert.is_false(called)
    end)

    it("calls execute when available() returns true", function()
      local called = false
      registry.register({
        id        = "test.avail",
        label     = "",
        desc      = "",
        category  = "diff",
        available = function(_view) return true end,
        execute   = function() called = true end,
      })
      registry.execute("test.avail", nil)
      assert.is_true(called)
    end)

    it("passes view as the first arg to available()", function()
      local seen_view = nil
      registry.register({
        id        = "test.view_arg",
        label     = "",
        desc      = "",
        category  = "diff",
        available = function(view) seen_view = view; return true end,
        execute   = function() end,
      })
      local fake_view = { kind = "diff" }
      registry.execute("test.view_arg", fake_view)
      assert.are.equal(fake_view, seen_view)
    end)
  end)

  describe("is_available", function()
    it("returns false for an unknown id", function()
      assert.is_false(registry.is_available("no.such"))
    end)

    it("returns true when no available predicate is set", function()
      registry.register({ id = "test.noav", label = "", desc = "", category = "diff", execute = function() end })
      assert.is_true(registry.is_available("test.noav"))
    end)

    it("delegates to the available predicate", function()
      registry.register({
        id        = "test.avpred",
        label     = "",
        desc      = "",
        category  = "diff",
        available = function(v) return v == "yes" end,
        execute   = function() end,
      })
      assert.is_false(registry.is_available("test.avpred", "no"))
      assert.is_true(registry.is_available("test.avpred", "yes"))
    end)
  end)

  describe("list", function()
    before_each(function()
      registry.register_all({
        { id = "l.diff1",  label = "", desc = "", category = "diff",      execute = function() end },
        { id = "l.diff2",  label = "", desc = "", category = "diff",      execute = function() end },
        { id = "l.hist1",  label = "", desc = "", category = "history",   execute = function() end },
        { id = "l.merge1", label = "", desc = "", category = "merge",     execute = function() end },
      })
    end)

    it("returns all actions when no category given", function()
      assert.are.equal(4, #registry.list())
    end)

    it("filters by category", function()
      local diff_list = registry.list("diff")
      assert.are.equal(2, #diff_list)
      for _, spec in ipairs(diff_list) do
        assert.are.equal("diff", spec.category)
      end
    end)

    it("returns results sorted by id", function()
      local all = registry.list()
      for i = 2, #all do
        assert.is_true(all[i-1].id <= all[i].id)
      end
    end)

    it("returns empty list when no actions match the category", function()
      assert.are.equal(0, #registry.list("navigation"))
    end)
  end)
end)
