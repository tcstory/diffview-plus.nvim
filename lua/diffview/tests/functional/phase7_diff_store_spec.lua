local DiffCommand = require("diffview.scene.views.diff.command")
local DiffStore = require("diffview.scene.views.diff.store").DiffStore
local FilePanel = require("diffview.scene.views.diff.file_panel").FilePanel
local component = require("diffview.ui.component")
local component_renderer = require("diffview.ui.component_renderer")
local router = require("diffview.ui.router")

local function file(path, kind)
  return { path = path, kind = kind or "working" }
end

local function files(entries)
  return {
    iter = function()
      local i = 0
      return function()
        i = i + 1
        if entries[i] then
          return i, entries[i]
        end
      end
    end,
  }
end

describe("Phase 7 DiffView state and controls", function()
  after_each(function()
    router._reset()
  end)

  it("owns files, reviewed visibility, filter, and current entry in one store", function()
    local lua = file("src/main.lua")
    local markdown = file("README.md")
    local store = DiffStore.new(files({ lua, markdown }) --[[@as FileDict]])

    store:set_current(lua)
    store:set_reviewed(lua, true)
    store:set_hide_reviewed(true)
    assert.equals(lua, store.current_entry)
    assert.is_false(store:is_visible(lua))
    assert.is_true(store:is_visible(markdown))

    store:set_hide_reviewed(false)
    store:set_filter("SRC/")
    assert.is_true(store:is_visible(lua))
    assert.is_false(store:is_visible(markdown))
  end)

  it("notifies subscribers with explicit state reasons", function()
    local entry = file("a.lua")
    local store = DiffStore.new(files({ entry }) --[[@as FileDict]])
    local reasons = {}
    local unsubscribe = store:subscribe(function(_, reason)
      reasons[#reasons + 1] = reason
    end)

    store:set_current(entry)
    store:toggle_reviewed(entry)
    store:set_filter("a")
    unsubscribe()
    store:set_hide_reviewed(true)

    assert.same({ "current", "reviewed", "filter" }, reasons)
  end)

  it("routes refresh sources through the command boundary", function()
    local seen_opts, seen_callback
    local view = {
      update_files = function(_, opts, callback)
        seen_opts, seen_callback = opts, callback
      end,
    }
    local callback = function() end

    DiffCommand.execute(view --[[@as DiffView]], {
      type = DiffCommand.Type.REFRESH,
      source = "gitsigns",
      opts = { force = true },
    }, callback)

    assert.same({ force = true }, seen_opts)
    assert.equals(callback, seen_callback)
  end)

  it("routes mutating actions as named commands", function()
    local event, value
    local view = {
      emitter = {
        emit = function(_, name, opts)
          event, value = name, opts
        end,
      },
    }

    DiffCommand.execute(view --[[@as DiffView]], {
      type = DiffCommand.Type.RESTORE,
      source = "user",
      opts = { selected = true },
    })

    assert.equals("restore_entry", event)
    assert.same({ selected = true }, value)
  end)

  it("projects nested components into owned clickable winbar routes", function()
    local owner = {}
    local root = component.new({
      identity = "toolbar",
      children = {
        component.new({
          identity = "refresh",
          text = "[Refresh]",
          action = "file.refresh_files",
        }),
      },
    })

    local winbar = component_renderer.winbar(root, owner)

    assert.truthy(winbar:find("%[Refresh%]"))
    assert.truthy(winbar:find("v:lua.DiffviewUIRouter", 1, true))
    assert.equals(1, router.size())
    router.unregister_owner(owner)
    assert.equals(0, router.size())
  end)

  it("exposes daily review operations in the file-panel toolbar", function()
    require("diffview.actions.builtins")
    local adapter = { ctx = { toplevel = "/tmp" } }
    local panel = FilePanel(adapter --[[@as VCSAdapter]], files({}) --[[@as FileDict]], {})
    panel.view = {
      dispatch_command = function() end,
      adapter = {
        supports = function()
          return true
        end,
      },
    } --[[@as DiffView]]

    local actions = {}
    for _, child in ipairs(component.children(panel:toolbar_component())) do
      actions[child.action] = true
    end

    for _, id in ipairs({
      "diff.toggle_select_entry",
      "diff.toggle_stage_entry",
      "file.restore_entry",
      "file.refresh_files",
      "file.filter_files",
      "file.listing_style",
      "file.toggle_flatten_dirs",
      "layout.cycle_layout",
      "file.goto_file_edit",
      "file.goto_file_split",
      "file.goto_file_tab",
    }) do
      assert.is_true(actions[id], id .. " should be visible")
    end
  end)
end)
