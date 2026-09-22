require("diffview.bootstrap")

local EventEmitter = require("diffview.events").EventEmitter
local lazy = require("diffview.lazy")

local Diff1 = lazy.access("diffview.scene.layouts.diff_1", "Diff1") ---@type Diff1|LazyModule
local Diff1Inline = lazy.access("diffview.scene.layouts.diff_1_inline", "Diff1Inline") ---@type Diff1Inline|LazyModule
local Diff1Raw = lazy.access("diffview.scene.layouts.diff_1_raw", "Diff1Raw") ---@type Diff1Raw|LazyModule
local Diff2 = lazy.access("diffview.scene.layouts.diff_2", "Diff2") ---@type Diff2|LazyModule
local Diff2Hor = lazy.access("diffview.scene.layouts.diff_2_hor", "Diff2Hor") ---@type Diff2Hor|LazyModule
local Diff2Ver = lazy.access("diffview.scene.layouts.diff_2_ver", "Diff2Ver") ---@type Diff2Ver|LazyModule
local Diff3 = lazy.access("diffview.scene.layouts.diff_3", "Diff3") ---@type Diff3|LazyModule
local Diff3Hor = lazy.access("diffview.scene.layouts.diff_3_hor", "Diff3Hor") ---@type Diff3Hor|LazyModule
local Diff3Mixed = lazy.access("diffview.scene.layouts.diff_3_mixed", "Diff3Mixed") ---@type Diff3Mixed|LazyModule
local Diff3Ver = lazy.access("diffview.scene.layouts.diff_3_ver", "Diff3Ver") ---@type Diff3Hor|LazyModule
local Diff4 = lazy.access("diffview.scene.layouts.diff_4", "Diff4") ---@type Diff4|LazyModule
local Diff4Mixed = lazy.access("diffview.scene.layouts.diff_4_mixed", "Diff4Mixed") ---@type Diff4Mixed|LazyModule
local utils = lazy.require("diffview.utils") ---@module "diffview.utils"

local M = {}

local setup_done = false

function M.diffview_callback(cb_name)
  error(
    ("diffview.config.diffview_callback('%s') was removed; use require('diffview.api').actions.callback('<action-id>')"):format(
      tostring(cb_name)
    ),
    2
  )
end

local defaults = require("diffview.config.defaults")
local migration = require("diffview.config.migration")

M.defaults = defaults

---@type EventEmitter
M.user_emitter = EventEmitter()
---@type DiffviewConfig
M._config = M.defaults

M.log_option_defaults = require("diffview.config.log_options")

---@return DiffviewConfig
function M.get_config()
  if not setup_done then
    M.setup()
  end

  return M._config
end

---@param single_file boolean
---@param t? LogOptions|LogOptions.user # Optional overrides; defaults to `{}`. The returned table is a deep copy callers may mutate safely.
---@param vcs "git"|"hg"|"jj"|"p4" # P4 reuses the `HgLogOptions` schema.
---@return LogOptions
function M.get_log_options(single_file, t, vcs)
  t = t or {}
  local log_options

  if single_file then
    log_options = M._config.file_history_panel.log_options[vcs].single_file
  else
    log_options = M._config.file_history_panel.log_options[vcs].multi_file
  end

  log_options = vim.tbl_extend("force", utils.tbl_deep_clone(log_options), t)

  for k, _ in pairs(log_options) do
    if t[k] == "" then
      log_options[k] = nil
    end
  end

  return log_options
end

---@alias LayoutName "diff1_plain"
---       | "diff1_inline"
---       | "diff1_raw"
---       | "diff2_horizontal"
---       | "diff2_vertical"
---       | "diff3_horizontal"
---       | "diff3_vertical"
---       | "diff3_mixed"
---       | "diff4_mixed"

local layout_map = {
  diff1_plain = Diff1,
  diff1_inline = Diff1Inline,
  diff1_raw = Diff1Raw,
  diff2_horizontal = Diff2Hor,
  diff2_vertical = Diff2Ver,
  diff3_horizontal = Diff3Hor,
  diff3_vertical = Diff3Ver,
  diff3_mixed = Diff3Mixed,
  diff4_mixed = Diff4Mixed,
}

---@param layout_name LayoutName
---@return Layout
function M.name_to_layout(layout_name)
  if tostring(layout_name):find("_pinned$", 1, false) then
    error(
      ("Layout '%s' was removed; use the corresponding standard layout with file-history pin_local mode"):format(
        layout_name
      ),
      2
    )
  end
  assert(layout_map[layout_name], "Invalid layout name: " .. layout_name)

  return layout_map[layout_name].__get()
end

---@param layout Layout
---@return table?
function M.get_layout_keymaps(layout)
  -- Check Diff1Inline before Diff1 since it's a subclass.
  if layout:instanceof(Diff1Inline.__get()) then
    return M._config.keymaps.diff1_inline
  elseif layout:instanceof(Diff1.__get()) then
    return M._config.keymaps.diff1
  elseif layout:instanceof(Diff2.__get()) then
    return M._config.keymaps.diff2
  elseif layout:instanceof(Diff3.__get()) then
    return M._config.keymaps.diff3
  elseif layout:instanceof(Diff4.__get()) then
    return M._config.keymaps.diff4
  end
end

function M.find_option_keymap(t)
  for _, mapping in ipairs(t) do
    if mapping[5] == "layout.options" then
      return mapping
    end
  end
end

function M.find_help_keymap(t)
  for _, mapping in ipairs(t) do
    if
      mapping[5] == "view.action_palette"
      or (type(mapping[4]) == "table" and mapping[4].desc == "Open the help panel")
    then
      return mapping
    end
  end
end

local validate = require("diffview.config.validate")

---@param ... table
---@return table
function M.extend_keymaps(...)
  local argc = select("#", ...)
  local argv = { ... }
  local contexts = {}

  for i = 1, argc do
    local cur = argv[i]
    if type(cur) == "table" then
      contexts[#contexts + 1] = { subject = cur, expanded = {} }
    end
  end

  for _, ctx in ipairs(contexts) do
    -- Expand the normal mode maps
    for lhs, rhs in pairs(ctx.subject) do
      if type(lhs) == "string" then
        ctx.expanded["n " .. lhs] = {
          "n",
          lhs,
          rhs,
          { silent = true, nowait = true },
        }
      end
    end

    for _, map in ipairs(ctx.subject) do
      for _, mode in ipairs(type(map[1]) == "table" and map[1] or { map[1] }) do
        ctx.expanded[mode .. " " .. map[2]] = utils.vec_join(mode, map[2], utils.vec_slice(map, 3))
      end
    end
  end

  local merged = vim.tbl_extend(
    "force",
    unpack(vim.tbl_map(function(v)
      return v.expanded
    end, contexts))
  )

  return vim.tbl_values(merged)
end

---@param user_config? DiffviewConfig.user
function M.setup(user_config)
  user_config = user_config or {}
  migration.check(user_config)

  M._config = vim.tbl_deep_extend("force", utils.tbl_deep_clone(M.defaults), user_config)
  ---@type EventEmitter
  M.user_emitter = EventEmitter()

  -- Coarse table guards for containers the deprecation block below indexes
  -- into. Without these, a malformed `file_panel`/`file_history_panel` (e.g.
  -- a boolean or number) would crash before per-field validation could fall
  -- back to defaults.
  validate.table(M._config, "file_panel", M.defaults.file_panel)
  validate.table(M._config, "file_history_panel", M.defaults.file_history_panel)

  -- ============================================================================
  -- Validation
  -- ============================================================================
  -- Each option is validated against its declared shape and falls back to the
  -- value declared in `M.defaults` (with `utils.warn`) when invalid. See the
  -- `validate.*` helpers near the top of this file for conventions.

  local c = M._config
  local d = M.defaults

  -- Top-level scalars and command lists.
  validate.boolean(c, "diff_binaries", d.diff_binaries)
  validate.boolean(c, "enhanced_diff_hl", d.enhanced_diff_hl)
  validate.string_list(c, "git_cmd", d.git_cmd)
  validate.string_list(c, "hg_cmd", d.hg_cmd)
  validate.string_list(c, "jj_cmd", d.jj_cmd)
  validate.string_list(c, "p4_cmd", d.p4_cmd)
  -- An empty command list would not be usable; substitute the default so the
  -- adapter detection logic later in setup can still pick an executable.
  for _, cmd_key in ipairs({ "git_cmd", "hg_cmd", "jj_cmd", "p4_cmd" }) do
    if #c[cmd_key] == 0 then
      c[cmd_key] = utils.tbl_deep_clone(d[cmd_key])
    end
  end
  validate.enum(c, "preferred_adapter", { "git", "hg", "jj", "p4" }, d.preferred_adapter, {
    nilable = true,
  })
  validate.integer(c, "rename_threshold", d.rename_threshold, {
    min = 0,
    max = 100,
    nilable = true,
  })
  validate.boolean(c, "use_icons", d.use_icons)
  validate.boolean(c, "show_help_hints", d.show_help_hints)
  validate.boolean(c, "show_root_path", d.show_root_path)
  validate.boolean(c, "watch_index", d.watch_index)
  validate.boolean(c, "hide_merge_artifacts", d.hide_merge_artifacts)
  validate.boolean(c, "auto_close_on_empty", d.auto_close_on_empty)
  validate.boolean(c, "wrap_entries", d.wrap_entries)
  validate.integer(c, "large_file_threshold", d.large_file_threshold, { min = 0 })
  validate.table(c, "diffopt", d.diffopt)
  validate.boolean(c, "clean_up_buffers", d.clean_up_buffers)
  validate.boolean(c, "restore_session", d.restore_session)

  -- persist_selections
  validate.table(c, "persist_selections", d.persist_selections)
  validate.boolean(c.persist_selections, "enabled", d.persist_selections.enabled, {
    path = "persist_selections.enabled",
  })
  validate.string(c.persist_selections, "path", d.persist_selections.path, {
    path = "persist_selections.path",
    nilable = true,
  })

  -- icons (folder icons)
  validate.table(c, "icons", d.icons)
  validate.string(c.icons, "folder_closed", d.icons.folder_closed, {
    path = "icons.folder_closed",
  })
  validate.string(c.icons, "folder_open", d.icons.folder_open, {
    path = "icons.folder_open",
  })

  -- status_icons: keys are git status codes (single chars like "A", "?"),
  -- values are display strings.
  validate.table(c, "status_icons", d.status_icons)
  for status_key in pairs(d.status_icons) do
    validate.string(c.status_icons, status_key, d.status_icons[status_key], {
      path = ("status_icons[%q]"):format(status_key),
    })
  end

  -- signs
  validate.table(c, "signs", d.signs)
  for sign_key in pairs(d.signs) do
    validate.string(c.signs, sign_key, d.signs[sign_key], {
      path = "signs." .. sign_key,
    })
  end

  -- view
  validate.table(c, "view", d.view)
  local view = c.view
  -- Concrete layout names. `view.*.layout` additionally accepts the `-1`
  -- "infer from diffopt" sentinel; `view.cycle_layouts.*` does not, since
  -- cycling needs concrete layouts to rotate through (`cycle_layout` drops
  -- any unresolvable entry).
  local standard_concrete = { "diff1_plain", "diff1_inline", "diff2_horizontal", "diff2_vertical" }
  local merge_concrete =
    { "diff1_plain", "diff3_horizontal", "diff3_vertical", "diff3_mixed", "diff4_mixed" }
  local standard_layouts = utils.vec_join(standard_concrete, -1)
  local merge_layouts = utils.vec_join(merge_concrete, -1)
  local layouts_for_kind = {
    default = standard_layouts,
    merge_tool = merge_layouts,
    file_history = standard_layouts,
  }
  for _, kind in ipairs({ "default", "merge_tool", "file_history" }) do
    validate.table(view, kind, d.view[kind], { path = "view." .. kind })
    validate.enum(view[kind], "layout", layouts_for_kind[kind], d.view[kind].layout, {
      path = ("view.%s.layout"):format(kind),
    })
    for _, flag in ipairs({ "disable_diagnostics", "winbar_info", "focus_diff" }) do
      validate.boolean(view[kind], flag, d.view[kind][flag], {
        path = ("view.%s.%s"):format(kind, flag),
      })
    end
  end
  -- `pin_local` is documented and defaulted only on `file_history`.
  validate.boolean(view.file_history, "pin_local", d.view.file_history.pin_local, {
    path = "view.file_history.pin_local",
  })

  validate.integer(view, "foldlevel", d.view.foldlevel, {
    min = 0,
    path = "view.foldlevel",
  })

  validate.enum(view, "one_sided_layout", { "default", "raw" }, d.view.one_sided_layout, {
    path = "view.one_sided_layout",
  })

  validate.table(view, "cycle_layouts", d.view.cycle_layouts, { path = "view.cycle_layouts" })
  validate.enum_list(
    view.cycle_layouts,
    "default",
    standard_concrete,
    d.view.cycle_layouts.default,
    { path = "view.cycle_layouts.default" }
  )
  validate.enum_list(
    view.cycle_layouts,
    "merge_tool",
    merge_concrete,
    d.view.cycle_layouts.merge_tool,
    { path = "view.cycle_layouts.merge_tool" }
  )
  -- Ensure each view's configured layout is in its corresponding cycle list,
  -- so `cycle_layout` (g<C-x>) can always rotate back to the starting layout.
  -- The sentinel `-1` ("infer from diffopt") is skipped since the concrete
  -- layout is not known at setup time. Iterate in a fixed order so shared
  -- cycle lists (e.g. `default` is used by both `default` and `file_history`)
  -- get deterministic entries.
  for _, item in ipairs({
    { kind = "default", cycle_key = "default" },
    { kind = "file_history", cycle_key = "default" },
    { kind = "merge_tool", cycle_key = "merge_tool" },
  }) do
    local layout = view[item.kind].layout
    local list = view.cycle_layouts[item.cycle_key]
    if layout and layout ~= -1 and not vim.tbl_contains(list, layout) then
      table.insert(list, layout)
    end
  end

  validate.table(view, "inline", d.view.inline, { path = "view.inline" })
  validate.enum(view.inline, "style", { "unified", "overleaf" }, d.view.inline.style, {
    path = "view.inline.style",
  })
  validate.enum(
    view.inline,
    "deletion_highlight",
    { "text", "full_width", "hanging" },
    d.view.inline.deletion_highlight,
    { path = "view.inline.deletion_highlight" }
  )
  validate.boolean(view.inline, "deletion_treesitter", d.view.inline.deletion_treesitter, {
    path = "view.inline.deletion_treesitter",
  })
  validate.boolean(view.inline, "fold_unchanged", d.view.inline.fold_unchanged, {
    path = "view.inline.fold_unchanged",
  })

  -- file_panel
  validate.table(c, "file_panel", d.file_panel)
  local file_panel = c.file_panel
  validate.enum(file_panel, "listing_style", { "tree", "list" }, d.file_panel.listing_style, {
    path = "file_panel.listing_style",
  })
  validate.any_of(file_panel, "sort_file", { "function" }, d.file_panel.sort_file, {
    nilable = true,
    path = "file_panel.sort_file",
  })
  validate.table(file_panel, "tree_options", d.file_panel.tree_options, {
    path = "file_panel.tree_options",
  })
  validate.boolean(
    file_panel.tree_options,
    "flatten_dirs",
    d.file_panel.tree_options.flatten_dirs,
    { path = "file_panel.tree_options.flatten_dirs" }
  )
  validate.enum(
    file_panel.tree_options,
    "folder_statuses",
    { "never", "only_folded", "always" },
    d.file_panel.tree_options.folder_statuses,
    { path = "file_panel.tree_options.folder_statuses" }
  )
  validate.enum(
    file_panel.tree_options,
    "folder_count_style",
    { "grouped", "simple", "none" },
    d.file_panel.tree_options.folder_count_style,
    { path = "file_panel.tree_options.folder_count_style" }
  )
  validate.boolean(
    file_panel.tree_options,
    "folder_trailing_slash",
    d.file_panel.tree_options.folder_trailing_slash,
    { path = "file_panel.tree_options.folder_trailing_slash" }
  )
  validate.table(file_panel, "list_options", d.file_panel.list_options, {
    path = "file_panel.list_options",
  })
  validate.enum(
    file_panel.list_options,
    "path_style",
    { "basename", "full" },
    d.file_panel.list_options.path_style,
    { path = "file_panel.list_options.path_style" }
  )
  validate.any_of(
    file_panel,
    "win_config",
    { "table", "function" },
    d.file_panel.win_config,
    { path = "file_panel.win_config" }
  )
  validate.boolean(file_panel, "show", d.file_panel.show, { path = "file_panel.show" })
  validate.boolean(
    file_panel,
    "always_show_sections",
    d.file_panel.always_show_sections,
    { path = "file_panel.always_show_sections" }
  )
  validate.boolean(file_panel, "always_show_marks", d.file_panel.always_show_marks, {
    path = "file_panel.always_show_marks",
  })
  validate.enum(
    file_panel,
    "mark_placement",
    { "inline", "sign_column" },
    d.file_panel.mark_placement,
    { path = "file_panel.mark_placement" }
  )
  validate.boolean(file_panel, "show_branch_name", d.file_panel.show_branch_name, {
    path = "file_panel.show_branch_name",
  })

  -- file_history_panel
  validate.table(c, "file_history_panel", d.file_history_panel)
  local fhp = c.file_history_panel
  validate.enum(
    fhp,
    "stat_style",
    { "number", "bar", "both" },
    d.file_history_panel.stat_style,
    { path = "file_history_panel.stat_style" }
  )
  validate.enum(
    fhp,
    "subject_highlight",
    { "ref_aware", "merge_aware", "plain" },
    d.file_history_panel.subject_highlight,
    { path = "file_history_panel.subject_highlight" }
  )
  validate.enum_list(
    fhp,
    "commit_format",
    { "status", "files", "stats", "hash", "reflog", "ref", "subject", "author", "date" },
    d.file_history_panel.commit_format,
    { path = "file_history_panel.commit_format" }
  )
  -- An empty `commit_format` would render commits with no info, so fall back
  -- to the default whether the user explicitly passed `{}` or filtering
  -- dropped every element.
  if #fhp.commit_format == 0 then
    utils.warn("Invalid value for 'file_history_panel.commit_format'. Must be a non-empty list.")
    fhp.commit_format = utils.tbl_deep_clone(d.file_history_panel.commit_format)
  end
  validate.table(fhp, "log_options", d.file_history_panel.log_options, {
    path = "file_history_panel.log_options",
  })
  -- Validate each per-VCS branch and its `single_file`/`multi_file` children
  -- before the merge loop below indexes and extends them. Without these,
  -- a config like `log_options = { git = 0 }` would crash setup.
  for _, vcs in ipairs({ "git", "hg", "jj", "p4" }) do
    validate.table(fhp.log_options, vcs, d.file_history_panel.log_options[vcs], {
      path = ("file_history_panel.log_options.%s"):format(vcs),
    })
    for _, name in ipairs({ "single_file", "multi_file" }) do
      validate.table(
        fhp.log_options[vcs],
        name,
        d.file_history_panel.log_options[vcs][name],
        { path = ("file_history_panel.log_options.%s.%s"):format(vcs, name) }
      )
    end
  end
  validate.any_of(
    fhp,
    "win_config",
    { "table", "function" },
    d.file_history_panel.win_config,
    { path = "file_history_panel.win_config" }
  )
  validate.boolean(fhp, "show", d.file_history_panel.show, { path = "file_history_panel.show" })
  validate.integer(
    fhp,
    "commit_subject_max_length",
    d.file_history_panel.commit_subject_max_length,
    { min = 0, path = "file_history_panel.commit_subject_max_length" }
  )
  validate.enum(
    fhp,
    "date_format",
    { "auto", "relative", "iso" },
    d.file_history_panel.date_format,
    { path = "file_history_panel.date_format" }
  )

  -- commit_log_panel
  validate.table(c, "commit_log_panel", d.commit_log_panel)
  validate.any_of(
    c.commit_log_panel,
    "win_config",
    { "table", "function" },
    d.commit_log_panel.win_config,
    { path = "commit_log_panel.win_config" }
  )

  -- default_args
  validate.table(c, "default_args", d.default_args)
  validate.string_list(c.default_args, "DiffviewOpen", d.default_args.DiffviewOpen, {
    path = "default_args.DiffviewOpen",
  })
  validate.string_list(
    c.default_args,
    "DiffviewFileHistory",
    d.default_args.DiffviewFileHistory,
    { path = "default_args.DiffviewFileHistory" }
  )

  -- Hooks and action-ID keymaps.
  validate.table(c, "hooks", d.hooks)
  validate.table(c, "keymaps", d.keymaps)
  local user_keymaps = type(user_config.keymaps) == "table" and user_config.keymaps or {}
  validate.enum(c.keymaps, "preset", { "minimal", "none" }, d.keymaps.preset, {
    path = "keymaps.preset",
  })
  validate.enum(
    c.keymaps,
    "interaction",
    { "mouse", "hybrid", "keyboard" },
    d.keymaps.interaction,
    { path = "keymaps.interaction" }
  )

  for _, name in ipairs({ "single_file", "multi_file" }) do
    for _, vcs in ipairs({ "git", "hg", "jj", "p4" }) do
      local t = M._config.file_history_panel.log_options[vcs]
      t[name] = vim.tbl_extend("force", utils.tbl_deep_clone(M.log_option_defaults[vcs]), t[name])
      for k, _ in pairs(t[name]) do
        if t[name][k] == "" then
          t[name][k] = nil
        end
      end
    end
  end

  for event, callback in pairs(M._config.hooks) do
    if type(callback) == "function" then
      M.user_emitter:on(event, function(_, ...)
        callback(...)
      end)
    end
  end

  local preset = M._config.keymaps.preset
  local interaction = M._config.keymaps.interaction
  M._config.keymaps = utils.tbl_deep_clone(M.defaults.keymaps)
  M._config.keymaps.preset = preset
  M._config.keymaps.interaction = interaction
  if preset == "none" then
    for name, keymaps in pairs(M._config.keymaps) do
      if type(keymaps) == "table" then
        M._config.keymaps[name] = {}
      end
    end
  end

  -- Merge default and user keymaps
  for name, keymap in pairs(M._config.keymaps) do
    if type(name) == "string" and type(keymap) == "table" then
      M._config.keymaps[name] = M.extend_keymaps(keymap, user_keymaps[name] or {})
    end
  end

  -- Disable keymaps set to `false`
  for name, keymaps in pairs(M._config.keymaps) do
    if type(name) == "string" and type(keymaps) == "table" then
      for i = #keymaps, 1, -1 do
        local v = keymaps[i]
        if type(v) == "table" then
          local lhs = v[2]
          local remove = not v[3]
            or (interaction == "keyboard" and lhs == "<LeftMouse>")
            or (interaction == "mouse" and lhs == "<cr>")
          if remove then
            table.remove(keymaps, i)
          end
        end
      end
      M._config.keymaps[name] = require("diffview.runtime.keymaps").resolve_all(keymaps)
    end
  end

  setup_done = true
end

-- Shared value validators. Used internally by `setup()` for the config schema,
-- and re-exported for CLI arg parsing (e.g., `--rename-threshold`) so both
-- surfaces produce the same warn-and-fallback behaviour.
M.validate = validate

return M
