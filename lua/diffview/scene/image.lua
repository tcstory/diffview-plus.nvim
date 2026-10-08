-- Optional Snacks renderer for Git image revisions. Binary bytes never enter
-- text buffers; each side owns a preview buffer and a temporary blob file.
local M = {}
local temporary_files = {}
local previews = {}
local attaching = {}
local formats =
  { png = true, jpg = true, jpeg = true, gif = true, webp = true, avif = true, svg = true }
local initialized = false

local function setup()
  if initialized then
    return
  end
  initialized = true
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("diffview_images", { clear = true }),
    callback = function()
      for src in pairs(temporary_files) do
        (vim.uv or vim.loop).fs_unlink(src)
      end
    end,
  })
end

---@param file vcs.File
---@param bufopts table
---@return integer? # A preview buffer, or nil to use normal file loading.
function M.create_buffer(file, bufopts)
  local snacks = rawget(_G, "Snacks")
  local RevType = require("diffview.vcs.rev").RevType
  if
    not snacks
    or not snacks.config.image.enabled
    or file.nulled
    or not formats[file.extension:lower()]
    or file.adapter.config_key ~= "git"
    or file.rev.type == RevType.CUSTOM
  then
    return
  end
  setup()
  local src = file.absolute_path
  local temporary = file.rev.type ~= RevType.LOCAL
  if temporary then
    local ref = file.rev:object_name() .. ":" .. file.path
    local cmd = vim.list_extend(vim.deepcopy(file.adapter:get_command()), { "show", ref })
    -- text=false preserves NULs and CRLFs in the Git blob.
    local result = vim.system(cmd, { cwd = file.adapter.ctx.toplevel, text = false }):wait()
    if result.code ~= 0 then
      -- Missing conflict stages use the normal null-side handling.
      return
    end
    src = vim.fn.tempname() .. "." .. file.extension
    local uv = vim.uv or vim.loop
    local fd = assert(uv.fs_open(src, "w", 384))
    local written, err = uv.fs_write(fd, result.stdout, 0)
    uv.fs_close(fd)
    if not written or written ~= #result.stdout then
      uv.fs_unlink(src)
      error(err or "Incomplete image blob write")
    end
    temporary_files[src] = true
  elseif vim.fn.filereadable(src) == 0 then
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  local ok, err = pcall(function()
    vim.api.nvim_buf_set_name(buf, "diffview-image://" .. buf .. "/" .. file.path)
    for key, value in pairs(bufopts) do
      vim.bo[buf][key] = value
    end
    vim.b[buf].diffview_image_src = src
    vim.b[buf].diffview_loaded = true
    vim.b[buf].autoformat = false
    file.binary = true
    file.winopts = vim.tbl_extend("force", file.winopts or {}, {
      diff = false,
      scrollbind = false,
      cursorbind = false,
      foldmethod = "manual",
      foldenable = false,
    })
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = buf,
      once = true,
      callback = function()
        snacks.image.placement.clean(buf)
        previews[buf] = nil
        attaching[buf] = nil
        if temporary then
          (vim.uv or vim.loop).fs_unlink(src)
          temporary_files[src] = nil
        end
      end,
    })
  end)
  if not ok then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    if temporary then
      (vim.uv or vim.loop).fs_unlink(src)
      temporary_files[src] = nil
    end
    error(err)
  end
  return buf
end

---@param pixels { width: number, height: number }
---@param cells { cell_width: number, cell_height: number }
---@param window { width: number, height: number }
---@return { width: integer, height: integer }
function M.fit_pixels(pixels, cells, window)
  local scale = math.min(
    1,
    window.width * cells.cell_width / pixels.width,
    window.height * cells.cell_height / pixels.height
  )
  -- Terminal placements occupy whole cells. Round down to avoid upscaling;
  -- images smaller than one cell necessarily occupy a single cell.
  return {
    width = math.max(1, math.floor(pixels.width * scale / cells.cell_width)),
    height = math.max(1, math.floor(pixels.height * scale / cells.cell_height)),
  }
end

---@param buf integer
function M.attach(buf)
  local snacks = rawget(_G, "Snacks")
  if not snacks or not snacks.config.image.enabled then
    return
  end
  local src = vim.b[buf].diffview_image_src
  if not src then
    return
  end
  local preview = previews[buf]
  if preview and not preview.closed then
    preview:show()
    preview:update()
    return
  end
  if attaching[buf] then
    return
  end
  attaching[buf] = true
  vim.b[buf].diffview_image_attached = true
  require("snacks.image.terminal").detect(function()
    attaching[buf] = nil
    if not vim.api.nvim_buf_is_valid(buf) or vim.b[buf].diffview_image_src ~= src then
      return
    end
    if not snacks.image.supports(src) then
      snacks.image.buf.attach(buf, { src = src })
      return
    end
    vim.bo[buf].filetype = "image"
    local preview = snacks.image.placement.new(buf, src, {
      conceal = true,
      auto_resize = true,
      on_update_pre = function(p)
        -- Snacks hides off-screen placements; a reused Diffview buffer must
        -- show them again, including when identify completes after a switch.
        if #p:wins() > 0 then
          p.hidden = false
        end
        -- The loading spinner isn't owned by placement.eids, so rendering
        -- the image does not remove it automatically in this Snacks version.
        local ns = vim.api.nvim_get_namespaces()["snacks.image"]
        if ns then
          for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
            for _, chunk in ipairs(mark[4].virt_text or {}) do
              if chunk[2] == "SnacksImageLoading" then
                vim.api.nvim_buf_del_extmark(buf, ns, mark[1])
                break
              end
            end
          end
        end
      end,
    })
    -- Keep Snacks' window/visibility handling, but size this placement from
    -- raw pixels. Its default state() applies image DPI and terminal scale,
    -- which can enlarge a 72-DPI image even when it already fits the window.
    local state = preview.state
    preview.state = function(p)
      local ret = state(p)
      local width, height = vim.o.columns, vim.o.lines
      for _, win in ipairs(p:wins()) do
        width = math.min(width, vim.api.nvim_win_get_width(win))
        height = math.min(height, vim.api.nvim_win_get_height(win))
      end
      local pixels = p.img.info and p.img.info.size or snacks.image.util.dim(p.img.file)
      local size =
        M.fit_pixels(pixels, snacks.image.terminal.size(), { width = width, height = height })
      ret.loc.width, ret.loc.height = size.width, size.height
      return ret
    end
    previews[buf] = preview
  end)
end

return M
