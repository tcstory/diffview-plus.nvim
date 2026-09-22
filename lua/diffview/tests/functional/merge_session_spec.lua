local helpers = require("diffview.tests.helpers")
local MergeSession = require("diffview.merge_session").MergeSession
local vcs = require("diffview.vcs")
local vcs_utils = require("diffview.vcs.utils")

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

  it("preserves manual worktree edits made before the merge session opens", function()
    repo = make_conflict_repo()
    local path = repo .. "/file.txt"
    local lines = vim.fn.readfile(path)
    local conflicts = vcs_utils.parse_conflicts(lines)
    eq(2, #conflicts)
    local first = conflicts[1]
    vim.fn.writefile(
      vim.list_extend(
        vim.list_extend(vim.list_slice(lines, 1, first.first - 1), { "manually resolved first" }),
        vim.list_slice(lines, first.last + 1)
      ),
      path
    )

    local err, adapter = vcs.get_adapter({ top_indicators = { repo } })
    assert.is_nil(err)
    local session = MergeSession(adapter, { "file.txt" })
    local entry = assert(session:get("file.txt"))

    eq(1, #entry.conflicts)
    assert.truthy(vim.tbl_contains(entry.result, "manually resolved first"))
  end)

  it("preserves an empty worktree result resolved before the session opens", function()
    repo = make_conflict_repo()
    vim.fn.writefile({}, repo .. "/file.txt", "b")

    local err, adapter = vcs.get_adapter({ top_indicators = { repo } })
    assert.is_nil(err)
    local session = MergeSession(adapter, { "file.txt" })
    local entry = assert(session:get("file.txt"))

    eq({}, entry.result)
    eq(0, session:counts())
  end)

  it(
    "tracks choices and applies all Result buffers only after every conflict is resolved",
    function()
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
    end
  )

  it("jumps past the current conflict when the cursor is inside a multi-line region", function()
    repo = make_conflict_repo()
    local err, adapter = vcs.get_adapter({ top_indicators = { repo } })
    assert.is_nil(err)

    local session = MergeSession(adapter, { "file.txt" })
    local entry = assert(session:get("file.txt"))
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, entry.result)
    session:attach("file.txt", bufnr, { stats = {} })

    local second = entry.conflicts[2]
    local start_row, end_row = session:_range(entry, second)
    vim.api.nvim_buf_set_lines(bufnr, start_row, end_row, false, {
      "second base line 1",
      "second base line 2",
      "second base line 3",
    })
    start_row, end_row = session:_range(entry, second)
    local cursor_row = start_row + 2
    assert.is_true(cursor_row - 1 >= start_row and cursor_row - 1 < end_row)

    local target_row, target_index = session:jump("file.txt", cursor_row, -1)
    local first_start_row = session:_range(entry, entry.conflicts[1])
    eq(1, target_index)
    eq(first_start_row + 1, target_row)

    target_row, target_index = session:jump("file.txt", cursor_row, 1)
    local second_start_row = session:_range(entry, entry.conflicts[2])
    eq(2, target_index)
    eq(second_start_row + 1, target_row)
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

  it("refuses to apply after the conflict stages change outside the session", function()
    repo = make_conflict_repo()
    local err, adapter = vcs.get_adapter({ top_indicators = { repo } })
    assert.is_nil(err)

    local session = MergeSession(adapter, { "file.txt" })
    local entry = assert(session:get("file.txt"))
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, entry.result)
    session:attach("file.txt", bufnr, { stats = {} })
    session:choose_all("file.txt", "ours")

    helpers.run({ "git", "add", "file.txt" }, repo)
    local ok, apply_err = session:apply()
    assert.is_false(ok)
    assert.truthy(apply_err:find("Git index changed", 1, true))
  end)

  it("coalesces choose_all change notifications", function()
    repo = make_conflict_repo()
    local err, adapter = vcs.get_adapter({ top_indicators = { repo } })
    assert.is_nil(err)

    local session = MergeSession(adapter, { "file.txt" })
    local entry = assert(session:get("file.txt"))
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, entry.result)
    session:attach("file.txt", bufnr, { stats = {} })

    local notifications = 0
    session.on_change = function()
      notifications = notifications + 1
    end
    session:choose_all("file.txt", "ours")
    eq(1, notifications)
  end)

  it("replaces the whole Result and resolves tracking when choosing an entire side", function()
    repo = make_conflict_repo()
    local err, adapter = vcs.get_adapter({ top_indicators = { repo } })
    assert.is_nil(err)

    local session = MergeSession(adapter, { "file.txt" })
    local entry = assert(session:get("file.txt"))
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, entry.result)
    session:attach("file.txt", bufnr, { stats = {} })

    session:choose_side("file.txt", "theirs")

    eq(0, session:counts())
    eq(entry.sides.theirs, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    for _, conflict in ipairs(entry.conflicts) do
      eq(true, conflict.resolved)
      eq("theirs", conflict.choice)
      eq(nil, conflict.extmark)
    end

    local ok, apply_err = session:apply()
    assert.is_true(ok, apply_err)
    eq(entry.sides.theirs, vim.fn.readfile(repo .. "/file.txt"))
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
    assert.equals(
      0,
      vim.fn.writefile(vim.fn.readfile(repo .. "/file.txt"), repo .. "/file.txt", "b")
    )

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

  it("preserves executable permissions and reports the metadata policy", function()
    repo = make_conflict_repo()
    local path = repo .. "/file.txt"
    assert(vim.uv.fs_chmod(path, 493)) -- 0755
    local err, adapter = vcs.get_adapter({ top_indicators = { repo } })
    assert.is_nil(err)
    local session = MergeSession(adapter, { "file.txt" })
    local entry = assert(session:get("file.txt"))
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, entry.result)
    session:attach("file.txt", bufnr, { stats = {} })
    session:choose_all("file.txt", "ours")

    local ok, apply_err, report = session:apply()
    assert.is_true(ok, apply_err)
    assert.equals(493, bit.band(assert(vim.uv.fs_stat(path)).mode, 511))
    assert.equals("preserved", report.metadata.permissions)
    assert.equals("rejected", report.metadata.symlinks)
    assert.truthy(report.metadata.acl_xattr:find("best%-effort"))
  end)

  it("rejects a symlink introduced after the transaction opens", function()
    repo = make_conflict_repo()
    local path = repo .. "/file.txt"
    local err, adapter = vcs.get_adapter({ top_indicators = { repo } })
    assert.is_nil(err)
    local session = MergeSession(adapter, { "file.txt" })
    local entry = assert(session:get("file.txt"))
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, entry.result)
    session:attach("file.txt", bufnr, { stats = {} })
    session:choose_all("file.txt", "ours")

    assert.equals(0, vim.fn.delete(path))
    assert(vim.uv.fs_symlink("target.txt", path))
    local ok, apply_err, report = session:apply()
    assert.is_false(ok)
    assert.truthy(apply_err:find("symlink", 1, true))
    assert.equals("worktree", session.transaction.stale["file.txt"].source)
    assert.equals("stale", report.status)
    assert.equals("target.txt", vim.uv.fs_readlink(path))
  end)

  it("handles both-added files with no stage 1 base", function()
    repo = helpers.init_repo()
    helpers.write(repo, "init.txt", { "init" })
    helpers.commit(repo, "root")
    local target_branch = helpers.run({ "git", "branch", "--show-current" }, repo)
    helpers.run({ "git", "branch", "feature" }, repo)

    helpers.write(repo, "added.txt", {
      "common header",
      "ours unique line",
      "common footer",
    })
    helpers.commit(repo, "add ours")

    helpers.run({ "git", "switch", "-q", "feature" }, repo)
    helpers.write(repo, "added.txt", {
      "common header",
      "theirs unique line",
      "common footer",
    })
    helpers.commit(repo, "add theirs")
    helpers.run({ "git", "switch", "-q", target_branch }, repo)
    helpers.system({ "git", "merge", "feature" }, repo, { allow_nonzero = true })

    local err, adapter = vcs.get_adapter({ top_indicators = { repo } })
    assert.is_nil(err)
    local session = MergeSession(adapter, { "added.txt" })
    local entry = assert(session:get("added.txt"))
    eq(1, #entry.conflicts)
    eq({ "common header", "common footer" }, entry.result)

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, entry.result)
    session:attach("added.txt", bufnr, { stats = {} })
    session:choose_all("added.txt", "ours")

    local ok, apply_err = session:apply()
    assert.is_true(ok, apply_err)
    eq({
      "common header",
      "ours unique line",
      "common footer",
    }, vim.fn.readfile(repo .. "/added.txt"))
  end)
end)
