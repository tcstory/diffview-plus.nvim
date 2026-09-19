--- Tests for runtime/fs.lua
---
--- Verifies that each fs.* function returns the correct result for known inputs.
--- Uses temporary files/directories created during the test so no external
--- fixtures are required.

local assert = require("luassert")

local fs = require("diffview.runtime.fs")

describe("diffview.runtime.fs", function()
  local tmpdir ---@type string

  before_each(function()
    tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, "p")
  end)

  after_each(function()
    pcall(vim.fn.delete, tmpdir, "rf")
  end)

  -- ── normalize ────────────────────────────────────────────────────────────

  describe("normalize()", function()
    it("returns the same path when already clean", function()
      local p = "/usr/local/bin"
      assert.equals(p, fs.normalize(p))
    end)

    it("collapses double slashes", function()
      local p = fs.normalize("/usr//local/bin")
      assert.is_nil(p:find("//"))
    end)
  end)

  -- ── join ─────────────────────────────────────────────────────────────────

  describe("join()", function()
    it("joins two segments", function()
      assert.equals("/a/b", fs.join("/a", "b"))
    end)

    it("joins three segments", function()
      assert.equals("/a/b/c", fs.join("/a", "b", "c"))
    end)
  end)

  -- ── dirname / basename ────────────────────────────────────────────────────

  describe("dirname()", function()
    it("returns the parent of a file path", function()
      assert.equals("/usr/local", fs.dirname("/usr/local/bin"))
    end)
  end)

  describe("basename()", function()
    it("returns the last component", function()
      assert.equals("bin", fs.basename("/usr/local/bin"))
    end)

    it("returns the file name with extension", function()
      assert.equals("foo.lua", fs.basename("/some/path/foo.lua"))
    end)
  end)

  -- ── exists / stat / filetype ──────────────────────────────────────────────

  describe("exists()", function()
    it("returns true for an existing directory", function()
      assert.is_true(fs.exists(tmpdir))
    end)

    it("returns false for a path that does not exist", function()
      assert.is_false(fs.exists(tmpdir .. "/nonexistent_file.txt"))
    end)
  end)

  describe("filetype()", function()
    it("returns 'directory' for a directory", function()
      assert.equals("directory", fs.filetype(tmpdir))
    end)

    it("returns 'file' for a regular file", function()
      local f = tmpdir .. "/test.txt"
      local fh = assert(io.open(f, "w"))
      fh:write("x")
      fh:close()
      assert.equals("file", fs.filetype(f))
    end)

    it("returns nil for a nonexistent path", function()
      assert.is_nil(fs.filetype(tmpdir .. "/no_such_thing"))
    end)
  end)

  describe("is_file()", function()
    it("returns true for a regular file", function()
      local f = tmpdir .. "/hello.lua"
      local fh = assert(io.open(f, "w"))
      fh:write("x")
      fh:close()
      assert.is_true(fs.is_file(f))
    end)

    it("returns false for a directory", function()
      assert.is_false(fs.is_file(tmpdir))
    end)
  end)

  describe("is_dir()", function()
    it("returns true for a directory", function()
      assert.is_true(fs.is_dir(tmpdir))
    end)

    it("returns false for a regular file", function()
      local f = tmpdir .. "/check.lua"
      local fh = assert(io.open(f, "w"))
      fh:write("x")
      fh:close()
      assert.is_false(fs.is_dir(f))
    end)
  end)

  -- ── readable ─────────────────────────────────────────────────────────────

  describe("readable()", function()
    it("returns true for a file the current user can read", function()
      local f = tmpdir .. "/readable.txt"
      local fh = assert(io.open(f, "w"))
      fh:write("readable")
      fh:close()
      assert.is_true(fs.readable(f))
    end)
  end)

  -- ── cwd ──────────────────────────────────────────────────────────────────

  describe("cwd()", function()
    it("returns a non-empty string", function()
      local cwd = fs.cwd()
      assert.is_string(cwd)
      assert.is_true(#cwd > 0)
    end)
  end)

  -- ── find_root ─────────────────────────────────────────────────────────────

  describe("find_root()", function()
    it("finds a marker file walking upward", function()
      -- Create a sentinel file in tmpdir.
      local marker = ".root_marker_test"
      local fh = assert(io.open(tmpdir .. "/" .. marker, "w"))
      fh:write("")
      fh:close()

      -- Create a nested subdirectory.
      local nested = tmpdir .. "/a/b/c"
      vim.fn.mkdir(nested, "p")

      local root = fs.find_root(nested, marker)
      -- Should resolve to tmpdir.
      assert.equals(fs.normalize(tmpdir), fs.normalize(root or ""))
    end)

    it("returns nil when the marker does not exist anywhere above", function()
      local root = fs.find_root(tmpdir, ".definitely_does_not_exist_xyzzy")
      assert.is_nil(root)
    end)
  end)
end)
