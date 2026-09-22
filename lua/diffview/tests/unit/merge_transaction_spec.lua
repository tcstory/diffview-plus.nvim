local MergeTransaction = require("diffview.domain.merge_transaction").MergeTransaction

describe("diffview.domain.merge_transaction", function()
  local function transaction()
    local entries = {
      ["a.txt"] = {
        path = "a.txt",
        conflicts = {
          { id = 1, resolved = false },
          { id = 2, resolved = false },
        },
      },
    }
    return MergeTransaction.new(entries, { "a.txt" }), entries["a.txt"]
  end

  it("tracks choices and navigates with stable identities", function()
    local tx, entry = transaction()
    assert.equals("a.txt#1", entry.conflicts[1].identity)
    assert.equals("a.txt#2", entry.conflicts[2].identity)

    local first, index, total = tx:navigate("a.txt", 1, true)
    assert.equals(entry.conflicts[1], first)
    assert.equals(1, index)
    assert.equals(2, total)

    tx:choose("a.txt", first.identity, "ours")
    local second = tx:navigate("a.txt", 1, true)
    assert.equals(entry.conflicts[2], second)
    assert.equals("a.txt#2", tx.active["a.txt"])
    assert.equals(1, tx:counts())
  end)

  it("records stale sources and apply lifecycle reports without Neovim state", function()
    local tx = transaction()
    tx:mark_stale("a.txt", "worktree", "changed")
    assert.equals("worktree", tx.stale["a.txt"].source)
    tx:set_report("failed", "stale", "changed")
    assert.equals("failed", tx.state)
    assert.equals("stale", tx.report.status)
    tx:clear_stale("a.txt")
    assert.is_nil(tx.stale["a.txt"])
  end)
end)
