local config = require("diffview.config")
local utils = require("diffview.utils")

describe("diffview.config", function()
  it("validates rename_threshold", function()
    local original = vim.deepcopy(config.get_config())
    local old_warn = utils.warn
    utils.warn = function() end

    local ok, err = pcall(function()
      config.setup({ rename_threshold = "40" })
      assert.equals(40, config.get_config().rename_threshold)

      config.setup({ rename_threshold = 101 })
      assert.is_nil(config.get_config().rename_threshold)

      config.setup({ rename_threshold = 12.5 })
      assert.is_nil(config.get_config().rename_threshold)
    end)

    utils.warn = old_warn
    config.setup(original)

    if not ok then
      error(err)
    end
  end)
end)

describe("diffview.config default keymaps", function()
  ---Search a keymap table for an entry with the given lhs binding.
  local function find_keymap(keymaps, lhs)
    for _, km in ipairs(keymaps) do
      if km[2] == lhs then
        return km
      end
    end
    return nil
  end

  it("uses the minimal preset and leaves ordinary diff buffers untouched", function()
    local keymaps = config.defaults.keymaps
    assert.equals("minimal", keymaps.preset)
    for _, group in ipairs({ "view", "diff1", "diff1_inline", "diff2", "diff3", "diff4" }) do
      assert.equals(0, #keymaps[group], group .. " must not receive domain mappings")
    end
  end)

  it("keeps only activation and palette keys in persistent panels", function()
    for _, group in ipairs({ "file_panel", "file_history_panel" }) do
      local maps = config.defaults.keymaps[group]
      assert.truthy(find_keymap(maps, "<cr>"))
      assert.truthy(find_keymap(maps, "<2-LeftMouse>"))
      assert.equals("view.action_palette", find_keymap(maps, "?")[3])
      assert.equals(3, #maps)
    end
  end)

  it("resolves user action IDs through the registry", function()
    local original = vim.deepcopy(config.get_config())
    local ok, err = pcall(function()
      config.setup({
        keymaps = {
          file_panel = {
            { "n", "s", "diff.toggle_stage_entry" },
          },
        },
      })

      local keymaps = config.get_config().keymaps.file_panel
      local mapping = find_keymap(keymaps, "s")
      assert.is_function(mapping[3])
      assert.equals("diff.toggle_stage_entry", mapping[5])
      assert.equals("Stage or unstage the selected entry.", mapping[4].desc)
    end)

    config.setup(original)
    if not ok then
      error(err)
    end
  end)

  it("the none preset installs only explicit user mappings", function()
    config.setup({ keymaps = { preset = "none", file_panel = { { "n", "x", "view.close" } } } })
    local maps = config.get_config().keymaps
    assert.equals("none", maps.preset)
    assert.equals(1, #maps.file_panel)
    assert.equals(0, #maps.file_history_panel)
  end)
end)
