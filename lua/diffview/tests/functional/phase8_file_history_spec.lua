local FileEntry = require("diffview.scene.file_entry").FileEntry
local FileHistoryPanel =
  require("diffview.scene.views.file_history.file_history_panel").FileHistoryPanel
local FileHistoryStore = require("diffview.scene.views.file_history.store").FileHistoryStore
local QueryStatus = require("diffview.scene.views.file_history.store").QueryStatus
local Diff2Hor = require("diffview.scene.layouts.diff_2_hor").Diff2Hor
local Diff2Ver = require("diffview.scene.layouts.diff_2_ver").Diff2Ver
local GitRev = require("diffview.vcs.adapters.git.rev").GitRev
local RevType = require("diffview.vcs.rev").RevType
local RenderData = require("diffview.ui.component_renderer").RenderData
local component = require("diffview.ui.component")

describe("Phase 8 file-history migration", function()
  it("tracks streaming progress and cooperative cancellation", function()
    local store = FileHistoryStore.new({ pin_local = true, pinned_path = "src/main.lua" })
    local token, generation = store:begin_query()

    assert.equals(QueryStatus.STREAMING, store.query.status)
    assert.is_true(store:append({ commit = { hash = "a" } } --[[@as LogEntry]], generation))
    assert.equals(1, store.query.received)
    assert.equals(1, #store.entries)

    assert.is_true(store:cancel_query("stop"))
    assert.is_true(token:is_cancelled())
    assert.equals("stop", token:reason())
    assert.equals(QueryStatus.CANCELLED, store.query.status)
    assert.is_false(store:append({} --[[@as LogEntry]], generation))
  end)

  it("ignores stale generations after a newer query starts", function()
    local store = FileHistoryStore.new()
    local old_token, old_generation = store:begin_query()
    local _, generation = store:begin_query()

    assert.is_true(old_token:is_cancelled())
    assert.is_false(store:append({} --[[@as LogEntry]], old_generation))
    assert.is_true(store:append({} --[[@as LogEntry]], generation))
  end)

  it("appends component nodes without rebuilding the history tree", function()
    local panel = setmetatable({
      entries = {},
      render_data = RenderData("phase8_incremental_components"),
      _component_entry_count = 0,
      _components_dirty = true,
    }, { __index = FileHistoryPanel })

    panel:update_components()
    local root = panel.components.comp
    local entries_root = panel.components.log.entries.comp
    for i = 1, 512 do
      panel.entries[#panel.entries + 1] = { commit = { hash = tostring(i) }, files = {} }
    end
    panel:update_components()

    assert.equals(root, panel.components.comp)
    assert.equals(entries_root, panel.components.log.entries.comp)
    assert.equals(512, #panel.components.log.entries)
    assert.equals(512, panel._component_entry_count)
  end)

  it("exposes filter, cancel, and commit context actions in the toolbar", function()
    require("diffview.actions.builtins")
    local store = FileHistoryStore.new()
    store:begin_query()
    local panel = setmetatable({
      store = store,
      parent = {
        panel = nil,
        adapter = {
          supports = function()
            return true
          end,
        },
      },
    }, { __index = FileHistoryPanel })
    panel.parent.panel = panel

    local actions = {}
    for _, child in ipairs(component.children(panel:toolbar_component())) do
      actions[child.action] = true
    end

    for _, id in ipairs({
      "history.filter",
      "history.cancel_query",
      "file.open_commit_log",
      "file.copy_hash",
      "diff.diff_against_head",
      "file.restore_entry",
    }) do
      assert.is_true(actions[id], id .. " should be visible")
    end
  end)

  it("stores pin-local ownership on standard layout instances", function()
    local path = vim.fn.tempname()
    vim.fn.writefile({ "working" }, path)
    local adapter = { ctx = { toplevel = "/" } }
    local pinned = { absolute_path = path, path = path }
    local entry = FileEntry.with_layout(Diff2Hor, {
      adapter = adapter --[[@as VCSAdapter]],
      path = path,
      status = "M",
      kind = "working",
      revs = {
        a = GitRev(RevType.COMMIT, "abc"),
        b = GitRev(RevType.LOCAL),
      },
      pinned_b_file = pinned --[[@as vcs.File]],
    })

    assert.equals(Diff2Hor, entry.layout.class)
    assert.same({ "b" }, entry.layout.shared_symbols)
    assert.is_true(entry.pin_local)
    entry:convert_layout(Diff2Ver)
    assert.equals(Diff2Ver, entry.layout.class)
    assert.same({ "b" }, entry.layout.shared_symbols)

    vim.fn.delete(path)
  end)
end)
