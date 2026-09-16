local helpers = require("diffview.tests.helpers")
local MergeSession = require("diffview.merge_session").MergeSession
local vcs = require("diffview.vcs")

local eq = helpers.eq

local function read_bytes(path)
  local stat = assert(vim.uv.fs_stat(path))
  local fd = assert(vim.uv.fs_open(path, "r", 0))
  local bytes = stat.size > 0 and assert(vim.uv.fs_read(fd, stat.size, 0)) or ""
  assert(vim.uv.fs_close(fd))
  return bytes
end

local function make_conflict_repo()
  local repo = helpers.init_repo()
  helpers.write(repo, "file.txt", {
    "top base",
    "top context 1",
    "top context 2",
    "top context 3",
    "top context 4",
    "first base",
    "middle 1",
    "middle 2",
    "middle 3",
    "middle 4",
    "second base",
    "bottom context 1",
    "bottom context 2",
    "bottom context 3",
    "bottom context 4",
    "bottom base",
  })
  helpers.commit(repo, "base")
  local target_branch = helpers.run({ "git", "branch", "--show-current" }, repo)
  helpers.run({ "git", "branch", "feature" }, repo)

  helpers.write(repo, "file.txt", {
    "top ours",
    "top context 1",
    "top context 2",
    "top context 3",
    "top context 4",
    "first ours",
    "middle 1",
    "middle 2",
    "middle 3",
    "middle 4",
    "second ours",
    "bottom context 1",
    "bottom context 2",
    "bottom context 3",
    "bottom context 4",
    "bottom base",
  })
  helpers.commit(repo, "ours")

  helpers.run({ "git", "switch", "-q", "feature" }, repo)
  helpers.write(repo, "file.txt", {
    "top base",
    "top context 1",
    "top context 2",
    "top context 3",
    "top context 4",
    "first theirs",
    "middle 1",
    "middle 2",
    "middle 3",
    "middle 4",
    "second theirs",
    "bottom context 1",
    "bottom context 2",
    "bottom context 3",
    "bottom context 4",
    "bottom theirs",
  })
  helpers.commit(repo, "theirs")
  helpers.run({ "git", "switch", "-q", target_branch }, repo)
  helpers.system({ "git", "merge", "feature" }, repo, { allow_nonzero = true })
  return repo
end

describe("diffview.merge_session", function()
  local repo

  after_each(function()
    if repo then
      helpers.cleanup_repo(repo)
    end
  end)

  it("builds an isolated Result with clean merges and BASE conflict placeholders", function()
    repo = make_conflict_repo()
    local err, adapter = vcs.get_adapter({ top_indicators = { repo } })
    assert.is_nil(err)

    local session = MergeSession(adapter, { "file.txt" })
    local entry = assert(session:get("file.txt"))
    eq({
      "top ours",
      "top context 1",
      "top context 2",
      "top context 3",
      "top context 4",
      "first base",
      "middle 1",
      "middle 2",
      "middle 3",
      "middle 4",
      "second base",
      "bottom context 1",
      "bottom context 2",
      "bottom context 3",
      "bottom context 4",
      "bottom theirs",
    }, entry.result)
    eq(2, #entry.conflicts)
    local unresolved, total = session:counts()
    eq(2, unresolved)
    eq(2, total)

    -- Constructing the session must not touch the real working-tree file.
    assert.truthy(table.concat(vim.fn.readfile(repo .. "/file.txt"), "\n"):find("<<<<<<<", 1, true))
  end)

  it("tracks choices and applies all Result buffers only after every conflict is resolved", function()
    repo = make_conflict_repo()
    local err, adapter = vcs.get_adapter({ top_indicators = { repo } })
    assert.is_nil(err)

    local session = MergeSession(adapter, { "file.txt" })
    local entry = assert(session:get("file.txt"))
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, entry.result)
    session:attach("file.txt", bufnr, { stats = {} })

    local ok, apply_err = session:apply()
    assert.is_false(ok)
    assert.truthy(apply_err:find("2 conflict", 1, true))

    assert.is_true(session:choose("file.txt", 6, "ours"))
    assert.is_true(session:choose("file.txt", 11, "theirs"))
    eq(0, session:counts())

    ok, apply_err = session:apply()
    assert.is_true(ok, apply_err)
    eq({
      "top ours",
      "top context 1",
      "top context 2",
      "top context 3",
      "top context 4",
      "first ours",
      "middle 1",
      "middle 2",
      "middle 3",
      "middle 4",
      "second theirs",
      "bottom context 1",
      "bottom context 2",
      "bottom context 3",
      "bottom context 4",
      "bottom theirs",
    }, vim.fn.readfile(repo .. "/file.txt"))
  end)

  it("refuses to overwrite a working-tree file changed outside the session", function()
    repo = make_conflict_repo()
    local err, adapter = vcs.get_adapter({ top_indicators = { repo } })
    assert.is_nil(err)

    local session = MergeSession(adapter, { "file.txt" })
    local entry = assert(session:get("file.txt"))
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, entry.result)
    session:attach("file.txt", bufnr, { stats = {} })
    session:choose_all("file.txt", "ours")

    helpers.write(repo, "file.txt", { "external change" })
    local ok, apply_err = session:apply()
    assert.is_false(ok)
    assert.truthy(apply_err:find("outside", 1, true))
    eq({ "external change" }, vim.fn.readfile(repo .. "/file.txt"))
  end)

  it("detects an external change that only removes the final newline", function()
    repo = make_conflict_repo()
    local err, adapter = vcs.get_adapter({ top_indicators = { repo } })
    assert.is_nil(err)

    local session = MergeSession(adapter, { "file.txt" })
    local entry = assert(session:get("file.txt"))
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, entry.result)
    session:attach("file.txt", bufnr, { stats = {} })
    session:choose_all("file.txt", "ours")

    local original = read_bytes(repo .. "/file.txt")
    assert.equals("\n", original:sub(-1))
    assert.equals(0, vim.fn.writefile(vim.fn.readfile(repo .. "/file.txt"), repo .. "/file.txt", "b"))

    local ok, apply_err = session:apply()
    assert.is_false(ok)
    assert.truthy(apply_err:find("outside", 1, true))
  end)

  it("preserves CRLF line endings when applying the Result", function()
    repo = make_conflict_repo()
    local path = repo .. "/file.txt"
    local conflict_bytes = read_bytes(path):gsub("\n", "\r\n")
    local fd = assert(vim.uv.fs_open(path, "w", 420))
    assert.equals(#conflict_bytes, vim.uv.fs_write(fd, conflict_bytes, 0))
    assert(vim.uv.fs_close(fd))

    local err, adapter = vcs.get_adapter({ top_indicators = { repo } })
    assert.is_nil(err)
    local session = MergeSession(adapter, { "file.txt" })
    local entry = assert(session:get("file.txt"))
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, entry.result)
    session:attach("file.txt", bufnr, { stats = {} })
    session:choose_all("file.txt", "ours")

    local ok, apply_err = session:apply()
    assert.is_true(ok, apply_err)
    local result = read_bytes(path)
    assert.truthy(result:find("\r\n", 1, true))
    assert.is_nil(result:find("[^\r]\n"))
  end)
end)
