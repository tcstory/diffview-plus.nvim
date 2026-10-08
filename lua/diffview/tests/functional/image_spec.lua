local async = require("diffview.async")
local image = require("diffview.scene.image")
local File = require("diffview.vcs.file").File
local GitAdapter = require("diffview.vcs.adapters.git").GitAdapter
local GitRev = require("diffview.vcs.adapters.git.rev").GitRev
local RevType = require("diffview.vcs.rev").RevType
local helpers = require("diffview.tests.helpers")

describe("Git image previews", function()
  local repo, adapter, saved_snacks, saved_terminal
  local files, buffers, placements, detections
  local blob = "\137PNG\r\n\26\n\0binary\r\nimage"

  before_each(function()
    repo = helpers.make_repo()
    adapter = GitAdapter({ toplevel = repo, cpath = repo, path_args = {} })
    files, buffers, placements, detections = {}, {}, {}, {}
    saved_snacks = rawget(_G, "Snacks")
    saved_terminal = package.loaded["snacks.image.terminal"]
    _G.Snacks = {
      config = { image = { enabled = true } },
      image = {
        supports = function()
          return true
        end,
        placement = {
          clean = function(buf)
            placements[buf] = nil
          end,
          new = function(buf, _, opts)
            local p = { hidden = true }
            function p:wins()
              return { 1 }
            end
            function p:show()
              self.hidden = false
            end
            function p:update()
              opts.on_update_pre(self)
            end
            p:update()
            placements[buf] = p
            return p
          end,
        },
      },
    }
    package.loaded["snacks.image.terminal"] = {
      detect = function(callback)
        detections[#detections + 1] = callback
      end,
    }
    local fd = assert(io.open(repo .. "/test.png", "wb"))
    fd:write(blob)
    fd:close()
    helpers.commit(repo, "image")
  end)

  after_each(function()
    for _, file in ipairs(files) do
      file:destroy(true)
    end
    for _, buf in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end
    _G.Snacks = saved_snacks
    package.loaded["snacks.image.terminal"] = saved_terminal
    vim.fn.delete(repo, "rf")
  end)

  local function make_file(rev, nulled)
    local file =
      File({ adapter = adapter, path = "test.png", kind = "working", rev = rev, nulled = nulled })
    files[#files + 1] = file
    return file
  end

  it(
    "preserves historical bytes and cleans the temporary blob",
    helpers.async_test(function()
      local file = make_file(GitRev(RevType.COMMIT, "HEAD"))
      local buf = async.await(file:create_buffer())
      local src = vim.b[buf].diffview_image_src
      local fd = assert(io.open(src, "rb"))
      assert.equals(blob, fd:read("*a"))
      fd:close()
      assert.is_true(file.loaded)
      assert.is_false(file.winopts.diff)
      assert.is_true(file.binary)
      file:destroy(true)
      assert.equals(0, vim.fn.filereadable(src))
    end)
  )

  it(
    "uses independent index and working-tree buffers without deleting the working file",
    helpers.async_test(function()
      local index = make_file(GitRev(RevType.STAGE, 0))
      local working = make_file(GitRev(RevType.LOCAL))
      local a = async.await(index:create_buffer())
      local b = async.await(working:create_buffer())
      assert.is_not.equals(a, b)
      assert.equals(repo .. "/test.png", vim.b[b].diffview_image_src)
      working:destroy(true)
      assert.equals(1, vim.fn.filereadable(repo .. "/test.png"))
    end)
  )

  it(
    "keeps missing sides and binaries without a renderer on the normal path",
    helpers.async_test(function()
      local missing = make_file(GitRev(RevType.COMMIT, "HEAD"), true)
      assert.equals(File._get_null_buffer(), async.await(missing:create_buffer()))
      _G.Snacks = nil
      local binary = make_file(GitRev(RevType.COMMIT, "HEAD"))
      assert.equals(File._get_null_buffer(), async.await(binary:create_buffer()))
    end)
  )

  it("restores hidden previews on revisit and removes only loading extmarks", function()
    local buf = vim.api.nvim_create_buf(false, true)
    buffers[#buffers + 1] = buf
    vim.b[buf].diffview_image_src = repo .. "/test.png"
    local ns = vim.api.nvim_create_namespace("snacks.image")
    local spinner = vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
      virt_text = { { "identify loading", "SnacksImageLoading" } },
    })
    local other = vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, { virt_text = { { "keep" } } })
    image.attach(buf)
    image.attach(buf)
    assert.equals(1, #detections)
    detections[1]()
    assert.is_false(placements[buf].hidden)
    assert.equals(0, #vim.api.nvim_buf_get_extmark_by_id(buf, ns, spinner, {}))
    assert.equals(2, #vim.api.nvim_buf_get_extmark_by_id(buf, ns, other, {}))
    placements[buf].hidden = true
    image.attach(buf)
    assert.is_false(placements[buf].hidden)
    assert.equals(1, #detections)
  end)

  it("ignores a detection callback after the preview buffer is wiped", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.b[buf].diffview_image_src = repo .. "/test.png"
    image.attach(buf)
    vim.api.nvim_buf_delete(buf, { force = true })
    detections[1]()
    assert.is_nil(placements[buf])
  end)
end)

describe("Image pixel sizing", function()
  local cells = { cell_width = 10, cell_height = 20 }

  it("keeps a fitting image at its raw pixel size", function()
    assert.same(
      { width = 30, height = 10 },
      image.fit_pixels({ width = 300, height = 200 }, cells, { width = 80, height = 24 })
    )
  end)

  it("shrinks a wide image proportionally to fit the window", function()
    assert.same(
      { width = 40, height = 10 },
      image.fit_pixels({ width = 1600, height = 800 }, cells, { width = 40, height = 20 })
    )
  end)

  it("shrinks a tall image proportionally to fit the window", function()
    assert.same(
      { width = 10, height = 20 },
      image.fit_pixels({ width = 400, height = 1600 }, cells, { width = 40, height = 20 })
    )
  end)

  it("rounds down to whole cells without enlarging an image", function()
    assert.same(
      { width = 30, height = 10 },
      image.fit_pixels({ width = 309, height = 219 }, cells, { width = 80, height = 24 })
    )
  end)
end)
