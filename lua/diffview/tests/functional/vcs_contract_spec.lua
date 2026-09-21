local Capability = require("diffview.vcs.capability").Capability
local GitAdapter = require("diffview.vcs.adapters.git").GitAdapter
local HgAdapter = require("diffview.vcs.adapters.hg").HgAdapter
local JjAdapter = require("diffview.vcs.adapters.jj").JjAdapter
local P4Adapter = require("diffview.vcs.adapters.p4").P4Adapter
local VCSAdapter = require("diffview.vcs.adapter").VCSAdapter
local path_args = require("diffview.vcs.path_args")
local query = require("diffview.vcs.query")
local git_status = require("diffview.vcs.adapters.git.status")

describe("VCS port contracts", function()
  describe("capabilities", function()
    it("declare features without adapter type checks", function()
      assert.is_true(GitAdapter.capabilities[Capability.STAGE])
      assert.is_true(GitAdapter.capabilities[Capability.TRANSACTIONAL_MERGE])
      assert.is_true(GitAdapter.capabilities[Capability.PIN_LOCAL])

      assert.is_nil(JjAdapter.capabilities[Capability.STAGE])
      assert.is_nil(HgAdapter.capabilities[Capability.STAGE])
      assert.is_nil(P4Adapter.capabilities[Capability.STAGE])
      assert.is_true(HgAdapter.capabilities[Capability.PIN_LOCAL])
      assert.is_nil(JjAdapter.capabilities[Capability.PIN_LOCAL])
      assert.is_nil(P4Adapter.capabilities[Capability.PIN_LOCAL])
    end)
  end)

  describe("literal-safe argv", function()
    it("preserves every path as one argument after the separator", function()
      local paths = { "-dash", "space name.lua", "line\nbreak.lua", "*.lua", ":(odd)name" }
      local args = path_args.append({ "status", "--porcelain" }, paths)

      assert.same({ "status", "--porcelain", "--", unpack(paths) }, args)
      assert.same(
        { "--", ":(literal)-dash", ":(literal)space name.lua" },
        path_args.git_literals({
          "-dash",
          "space name.lua",
        })
      )
    end)
  end)

  describe("structured query result", function()
    it("short-circuits a cancelled query without spawning a process", function()
      local adapter = VCSAdapter()
      adapter.config_key = "fake"
      local executed = false
      adapter.exec_sync = function()
        executed = true
        return {}, 0, {}
      end
      local token = query.CancellationToken.new()
      token:cancel("test cancellation")

      local result = adapter:query({ "status" }, { token = token, operation = "status" })

      assert.is_false(result.ok)
      assert.equals(query.ErrorKind.CANCELLED, result.error.kind)
      assert.equals("test cancellation", result.error.message)
      assert.is_false(executed)
    end)

    it("returns execution details without presenting the error", function()
      local adapter = VCSAdapter()
      adapter.config_key = "fake"
      adapter.exec_sync = function()
        return {}, 7, { "bad revision" }
      end

      local result = adapter:query({ "show", "bad" }, { operation = "revision" })

      assert.is_false(result.ok)
      assert.equals(query.ErrorKind.EXEC, result.error.kind)
      assert.equals(7, result.error.code)
      assert.same({ "bad revision" }, result.error.stderr)
    end)
  end)

  describe("pure Git status parsers", function()
    local names = {
      "plain.lua",
      "space name.lua",
      "tab\tname.lua",
      "line\nbreak.lua",
      "-leading.lua",
      "*.lua",
      "unicodé/文件.lua",
    }

    it("round-trips arbitrary NUL-delimited file names", function()
      for _, name in ipairs(names) do
        local entries = git_status.parse_name_status("M\0" .. name .. "\0")
        assert.equals(1, #entries)
        assert.equals("M", entries[1].status)
        assert.equals(name, entries[1].name)
      end
    end)

    it("round-trips rename pairs and keeps stats aligned", function()
      for i, name in ipairs(names) do
        local oldname = "old/" .. name
        local entries = git_status.parse_name_status("R100\0" .. oldname .. "\0" .. name .. "\0")
        local stats, count = git_status.parse_numstat(i .. "\t" .. (i + 1) .. "\t" .. name .. "\0")

        assert.equals(name, entries[1].name)
        assert.equals(oldname, entries[1].oldname)
        assert.equals(1, count)
        assert.same({ additions = i, deletions = i + 1 }, stats[1])
      end
    end)

    it("represents binary stats without inventing line counts", function()
      local stats, count = git_status.parse_numstat("-\t-\tbinary.dat\0")
      assert.equals(1, count)
      assert.is_nil(stats[1])
    end)
  end)
end)
