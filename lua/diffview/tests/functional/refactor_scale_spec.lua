local DiffStore = require("diffview.scene.views.diff.store").DiffStore
local FileHistoryStore = require("diffview.scene.views.file_history.store").FileHistoryStore
local MergeTransaction = require("diffview.domain.merge_transaction").MergeTransaction

describe("refactor scale contracts", function()
  it("filters and prunes 1000 diff entries within the baseline budget", function()
    local entries = {}
    for index = 1, 1000 do
      entries[index] = { path = ("src/file_%04d.lua"):format(index), kind = "working" }
    end
    local files = {
      iter = function()
        local index = 0
        return function()
          index = index + 1
          if entries[index] then
            return index, entries[index]
          end
        end
      end,
    }
    local store = DiffStore.new(files --[[@as FileDict]])
    for index = 1, #entries, 2 do
      store:set_reviewed(entries[index] --[[@as FileEntry]], true)
    end

    local started = vim.uv.hrtime()
    store:set_filter("file_09")
    store:prune_reviewed()
    local elapsed_ms = (vim.uv.hrtime() - started) / 1000000

    assert.is_true(store:is_visible(entries[900] --[[@as FileEntry]]))
    assert.is_true(elapsed_ms < 100, ("1000-entry store update took %.2fms"):format(elapsed_ms))
  end)

  it("streams 1000 history entries without replacing existing state", function()
    local store = FileHistoryStore.new()
    local _, generation = store:begin_query()
    local started = vim.uv.hrtime()
    for index = 1, 1000 do
      assert.is_true(
        store:append({ commit = { hash = tostring(index) } } --[[@as LogEntry]], generation)
      )
    end
    local elapsed_ms = (vim.uv.hrtime() - started) / 1000000

    assert.equals(1000, #store.entries)
    assert.equals(1000, store.query.received)
    assert.is_true(elapsed_ms < 100, ("1000-entry history append took %.2fms"):format(elapsed_ms))
  end)

  it("tracks and resolves 100 merge conflicts within the baseline budget", function()
    local conflicts = {}
    for index = 1, 100 do
      conflicts[index] = { id = index, resolved = false }
    end
    local entries = { ["conflicted.txt"] = { path = "conflicted.txt", conflicts = conflicts } }
    local started = vim.uv.hrtime()
    local transaction = MergeTransaction.new(entries --[[@as table<string, MergeSession.Entry>]], {
      "conflicted.txt",
    })
    for index = 1, 100 do
      transaction:choose("conflicted.txt", "conflicted.txt#" .. index, "ours")
    end
    local elapsed_ms = (vim.uv.hrtime() - started) / 1000000
    local unresolved, total = transaction:counts()

    assert.equals(0, unresolved)
    assert.equals(100, total)
    assert.is_true(elapsed_ms < 100, ("100-conflict transaction took %.2fms"):format(elapsed_ms))
  end)
end)
