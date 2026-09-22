---Configuration schema annotations and immutable default values.
---Does not own runtime configuration or user hooks.

local M = {}

-- Layout aliases used across multiple view kinds and cycle_layouts. The
-- pinned variants (`diff1_*_pinned`, `diff2_*_pinned`) intentionally
-- aren't listed here: they're internal to file-history `pin_local` mode
-- and are selected by the view based on whether `--pin-local` is active,
-- not by direct user configuration. The `LayoutName` alias below still
-- includes them so `name_to_layout` can resolve them internally.
---@alias DiffviewStandardLayout "diff1_plain"|"diff1_inline"|"diff2_horizontal"|"diff2_vertical"
---@alias DiffviewMergeLayout "diff1_plain"|"diff3_horizontal"|"diff3_vertical"|"diff3_mixed"|"diff4_mixed"
---@alias DiffviewInferredLayout -1
---@alias DiffviewOneSidedLayout "default"|"raw"

-- Targets consumed by action factories in `actions.lua` (referenced from keymaps).
---@alias DiffviewConflictTarget "ours"|"theirs"|"base"|"all"|"none"
---@alias DiffviewConflictSideTarget "ours"|"theirs"|"base"
---@alias DiffviewDiffgetTarget "ours"|"theirs"|"base"|"local"

---@class DiffviewKeymapOpts
---@field desc? string
---@field silent? boolean
---@field nowait? boolean
---@field noremap? boolean
---@field expr? boolean
---@field buffer? integer|boolean

---@class DiffviewKeymapEntry
---@field [1] string|string[] Mode(s).
---@field [2] string Left-hand side.
---@field [3] string|(fun(...): any?)|false Action ID, raw rhs, callback, or `false` to disable.
---@field [4]? DiffviewKeymapOpts
---@field [5]? string Resolved action ID (internal).

---@class DiffviewConfig
---@field diff_binaries boolean
---@field enhanced_diff_hl boolean
---@field git_cmd string[]
---@field hg_cmd string[]
---@field jj_cmd string[]
---@field p4_cmd string[]
---@field preferred_adapter? DiffviewPreferredAdapter
---@field rename_threshold? integer
---@field use_icons boolean
---@field show_help_hints boolean
---@field show_root_path boolean
---@field watch_index boolean
---@field hide_merge_artifacts boolean
---@field auto_close_on_empty boolean
---@field wrap_entries boolean
---@field large_file_threshold integer
---@field diffopt table
---@field clean_up_buffers boolean
---@field persist_selections DiffviewPersistSelectionsConfig
---@field restore_session boolean
---@field icons DiffviewIcons
---@field status_icons DiffviewStatusIcons
---@field signs DiffviewSigns
---@field view DiffviewViewConfig
---@field file_panel DiffviewFilePanelConfig
---@field file_history_panel DiffviewFileHistoryPanelConfig
---@field commit_log_panel DiffviewCommitLogPanelConfig
---@field default_args DiffviewDefaultArgs
---@field hooks DiffviewHooks
---@field keymaps DiffviewKeymapsConfig

---@class DiffviewConfig.user
---@field diff_binaries? boolean Show diffs for binary files.
---@field enhanced_diff_hl? boolean See `|diffview-config-enhanced_diff_hl|`.
---@field git_cmd? string[] The git executable followed by default args.
---@field hg_cmd? string[] The hg executable followed by default args.
---@field jj_cmd? string[] The jj executable followed by default args.
---@field p4_cmd? string[] The p4 executable followed by default args.
---@field preferred_adapter? DiffviewPreferredAdapter Preferred VCS adapter; tried first when detecting repos.
---@field rename_threshold? integer Rename detection similarity (0-100). Nil uses git default (50%).
---@field use_icons? boolean Requires nvim-web-devicons or mini.icons.
---@field show_help_hints? boolean Show hints for how to open the help panel.
---@field show_root_path? boolean Show repository root path in panel headers.
---@field watch_index? boolean Update views and index buffers when the git index changes.
---@field hide_merge_artifacts? boolean Hide merge artifact files (*.orig, *.BACKUP.*, *.BASE.*, *.LOCAL.*, *.REMOTE.*).
---@field auto_close_on_empty? boolean Close diffview when the last file is staged/resolved.
---@field wrap_entries? boolean Wrap around when navigating past the first/last file entry.
---@field large_file_threshold? integer Line count above which treesitter is disabled on non-LOCAL diff buffers. 0 disables this behaviour.
---@field diffopt? table Override `diffopt` while diffview is open. Restored on close.
---@field clean_up_buffers? boolean Delete file buffers created by diffview on close.
---@field persist_selections? DiffviewPersistSelectionsConfig.user Persist file selections and hide-reviewed state across Neovim restarts.
---@field restore_session? boolean Restore open Diffview/FileHistory views from a sourced Vim session.
---@field icons? DiffviewIcons.user Folder icons; only applies when `use_icons` is true.
---@field status_icons? DiffviewStatusIcons.user Icons for git status letters.
---@field signs? DiffviewSigns.user Sign characters used throughout the UI.
---@field view? DiffviewViewConfig.user Layout and behaviour of different view types.
---@field file_panel? DiffviewFilePanelConfig.user File panel configuration.
---@field file_history_panel? DiffviewFileHistoryPanelConfig.user File history panel configuration.
---@field commit_log_panel? DiffviewCommitLogPanelConfig.user Commit log panel configuration.
---@field default_args? DiffviewDefaultArgs.user Default args prepended to the arg-list for `:DiffviewOpen` / `:DiffviewFileHistory`.
---@field hooks? DiffviewHooks Event hooks. See `|diffview-config-hooks|`.
---@field keymaps? DiffviewKeymapsConfig.user Action-ID keymaps using the `minimal` or `none` preset.

---@type DiffviewConfig
M.defaults = {
  diff_binaries = false,
  enhanced_diff_hl = false,
  git_cmd = { "git" },
  hg_cmd = { "hg" },
  jj_cmd = { "jj" },
  p4_cmd = { "p4" },
  ---@alias DiffviewPreferredAdapter "git"|"hg"|"jj"|"p4"
  preferred_adapter = nil, -- Preferred VCS adapter ("git", "hg", "jj", "p4"). Tried first when detecting repos.
  rename_threshold = nil, -- Similarity threshold for rename detection (e.g. 40 for 40%). Nil uses git default (50%).
  use_icons = true,
  show_help_hints = true,
  show_root_path = true, -- Show repository root path in panel headers.
  watch_index = true,
  hide_merge_artifacts = false, -- Hide merge artifact files (*.orig, *.BACKUP.*, etc.)
  auto_close_on_empty = false, -- Automatically close diffview when the last file is staged/resolved.
  wrap_entries = true, -- Wrap around when navigating past the first/last file entry.
  -- Line count threshold for disabling treesitter highlighting on non-LOCAL
  -- revision buffers. Set to 0 to disable this behaviour.
  large_file_threshold = 0,
  -- Override diffopt settings while diffview is open. Restored on close.
  -- Keys: algorithm, context, linematch, indent_heuristic, iwhite, iwhiteall,
  -- iwhiteeol, iblank, icase.
  -- Example: { algorithm = "histogram", linematch = 60 }
  diffopt = {},
  clean_up_buffers = false, -- Delete file buffers created by diffview on close (only buffers not open before diffview).

  ---@class DiffviewPersistSelectionsConfig
  ---@field enabled boolean
  ---@field path? string

  ---@class DiffviewPersistSelectionsConfig.user
  ---@field enabled? boolean Persist file selections and hide-reviewed state across Neovim restarts.
  ---@field path? string Storage path. Nil uses `stdpath("data") .. "/diffview_selections.json"`.
  persist_selections = {
    enabled = false, -- Persist file selections and hide-reviewed state across Neovim restarts.
    path = nil, -- Storage path. Nil uses stdpath("data") .. "/diffview_selections.json".
  },
  restore_session = true, -- Restore open Diffview/FileHistory views from a sourced Vim session.

  ---@class DiffviewIcons
  ---@field folder_closed string
  ---@field folder_open string

  ---@class DiffviewIcons.user
  ---@field folder_closed? string Icon for a collapsed folder.
  ---@field folder_open? string Icon for an expanded folder.
  icons = {
    folder_closed = "",
    folder_open = "",
  },

  ---@class DiffviewStatusIcons
  ---@field ["A"] string Added.
  ---@field ["?"] string Untracked.
  ---@field ["M"] string Modified.
  ---@field ["R"] string Renamed.
  ---@field ["C"] string Copied.
  ---@field ["T"] string Type changed.
  ---@field ["U"] string Unmerged.
  ---@field ["X"] string Unknown.
  ---@field ["D"] string Deleted.
  ---@field ["B"] string Broken.
  ---@field ["!"] string Ignored.

  ---@class DiffviewStatusIcons.user
  ---@field ["A"]? string Added.
  ---@field ["?"]? string Untracked.
  ---@field ["M"]? string Modified.
  ---@field ["R"]? string Renamed.
  ---@field ["C"]? string Copied.
  ---@field ["T"]? string Type changed.
  ---@field ["U"]? string Unmerged.
  ---@field ["X"]? string Unknown.
  ---@field ["D"]? string Deleted.
  ---@field ["B"]? string Broken.
  ---@field ["!"]? string Ignored.
  status_icons = {
    ["A"] = "A", -- Added
    ["?"] = "?", -- Untracked
    ["M"] = "M", -- Modified
    ["R"] = "R", -- Renamed
    ["C"] = "C", -- Copied
    ["T"] = "T", -- Type changed
    ["U"] = "U", -- Unmerged
    ["X"] = "X", -- Unknown
    ["D"] = "D", -- Deleted
    ["B"] = "B", -- Broken
    ["!"] = "!", -- Ignored
  },

  ---@class DiffviewSigns
  ---@field fold_closed string
  ---@field fold_open string
  ---@field done string
  ---@field selected_file string
  ---@field unselected_file string
  ---@field selected_dir string
  ---@field partially_selected_dir string
  ---@field unselected_dir string

  ---@class DiffviewSigns.user
  ---@field fold_closed? string Sign for a closed fold.
  ---@field fold_open? string Sign for an open fold.
  ---@field done? string Sign for a completed item (e.g. resolved conflict).
  ---@field selected_file? string Sign for a selected file mark.
  ---@field unselected_file? string Sign for an unselected file mark.
  ---@field selected_dir? string Sign for a fully selected directory.
  ---@field partially_selected_dir? string Sign for a partially selected directory.
  ---@field unselected_dir? string Sign for an unselected directory.
  signs = {
    fold_closed = "",
    fold_open = "",
    done = "✓",
    selected_file = "■",
    unselected_file = "□",
    selected_dir = "■",
    partially_selected_dir = "▣",
    unselected_dir = "□",
  },

  ---@class DiffviewViewConfig
  ---@field default DiffviewStandardViewTypeConfig
  ---@field merge_tool DiffviewMergeViewTypeConfig
  ---@field file_history DiffviewStandardViewTypeConfig
  ---@field foldlevel integer
  ---@field one_sided_layout DiffviewOneSidedLayout
  ---@field cycle_layouts DiffviewCycleLayouts
  ---@field inline DiffviewInlineConfig

  ---@class DiffviewViewConfig.user
  ---@field default? DiffviewStandardViewTypeConfig.user Config for changed files, and staged files in diff views.
  ---@field merge_tool? DiffviewMergeViewTypeConfig.user Config for conflicted files in diff views during a merge or rebase.
  ---@field file_history? DiffviewStandardViewTypeConfig.user Config for changed files in file history views.
  ---@field foldlevel? integer See `|diffview-config-view.foldlevel|`.
  ---@field one_sided_layout? DiffviewOneSidedLayout Layout used for files whose diff is one-sided (status `A`/`?` or `D`). `"default"` keeps the configured layout (a Diff2 leaves an empty pane; a `diff1_plain` keeps its diff-mode chrome). `"raw"` substitutes `diff1_raw`: a single non-diff window where `A`/`?` shows the b-side directly (editable working-tree buffer when b is `LOCAL`, read-only when b is a commit rev) and `D` shows the pre-deletion content from `revs.a` (read-only when that's a commit; editable when it's the index, with `:w` writing back via the usual STAGE-0 path). Applies to both diff views and file history views, and to `diff1_plain` and Diff2 base layouts. Has no effect on `diff1_inline` (which already renders one-sided content coherently), on renames, modifications, merge conflicts, or when file history's `pin_local` mode owns the right-hand window. See `|diffview-config-view.one_sided_layout|`.
  ---@field cycle_layouts? DiffviewCycleLayouts.user Layouts to cycle through with `cycle_layout`.
  ---@field inline? DiffviewInlineConfig.user Options that apply to the `diff1_inline` layout.
  view = {
    ---@class DiffviewStandardViewTypeConfig
    ---@field layout DiffviewStandardLayout|DiffviewInferredLayout
    ---@field disable_diagnostics boolean
    ---@field winbar_info boolean
    ---@field focus_diff boolean
    ---@field pin_local? boolean

    ---@class DiffviewMergeViewTypeConfig
    ---@field layout DiffviewMergeLayout|DiffviewInferredLayout
    ---@field disable_diagnostics boolean
    ---@field winbar_info boolean
    ---@field focus_diff boolean

    ---@class DiffviewStandardViewTypeConfig.user
    ---@field layout? DiffviewStandardLayout|DiffviewInferredLayout Layout to use for this view type. See `|diffview-config-view.x.layout|`.
    ---@field disable_diagnostics? boolean Temporarily disable diagnostics for diff buffers while in the view.
    ---@field winbar_info? boolean See `|diffview-config-view.x.winbar_info|`.
    ---@field focus_diff? boolean Focus the main diff window on open instead of the file panel.
    ---@field pin_local? boolean File-history only: pin the b-window to the working-tree LOCAL buffer across log navigation, so you can browse history while diffing each commit against your live file. Per-invocation, `--pin-local` enables and `--pin-local=false` disables (overriding any value set here). For git, `--base=<rev>` is an alternative that pins to a fixed commit instead. See `|diffview-config-view.file_history.pin_local|`.

    ---@class DiffviewMergeViewTypeConfig.user
    ---@field layout? DiffviewMergeLayout|DiffviewInferredLayout Layout to use for this view type. See `|diffview-config-view.x.layout|`.
    ---@field disable_diagnostics? boolean Temporarily disable diagnostics for diff buffers while in the view.
    ---@field winbar_info? boolean See `|diffview-config-view.x.winbar_info|`.
    ---@field focus_diff? boolean Focus the main diff window on open instead of the file panel.

    ---@type DiffviewStandardViewTypeConfig
    default = {
      layout = "diff2_horizontal",
      disable_diagnostics = false,
      winbar_info = false,
      focus_diff = false,
    },
    merge_tool = {
      layout = "diff3_horizontal",
      disable_diagnostics = true,
      winbar_info = true,
      focus_diff = false,
    },
    file_history = {
      layout = "diff2_horizontal",
      disable_diagnostics = false,
      winbar_info = false,
      focus_diff = false,
      pin_local = false,
    },
    -- Initial 'foldlevel' for diff buffers. Default 0 collapses unchanged
    -- regions; set to a high value (e.g. 99) to keep all folds open.
    foldlevel = 0,
    -- Layout used for files whose diff is one-sided (added, untracked, or
    -- deleted). `"default"` keeps the configured layout. `"raw"` substitutes
    -- `diff1_raw`: a single non-diff window where additions and untracked
    -- files open as editable buffers backed by the file on disk, and
    -- deletions show the pre-deletion content from `revs.a` (read-only
    -- against a commit; editable against the index, with `:w` writing
    -- back via the usual STAGE-0 path). Applies to `diff1_plain` and
    -- Diff2 base layouts; `diff1_inline` (which renders one-sided content
    -- as all-added or all-deleted virt_lines) is left alone.
    one_sided_layout = "default",

    ---@class DiffviewCycleLayouts
    ---@field default DiffviewStandardLayout[]
    ---@field merge_tool DiffviewMergeLayout[]

    ---@class DiffviewCycleLayouts.user
    ---@field default? DiffviewStandardLayout[] Layouts cycled by `cycle_layout` in standard views.
    ---@field merge_tool? DiffviewMergeLayout[] Layouts cycled by `cycle_layout` in conflict views.
    -- Layouts to cycle through with `cycle_layout` action.
    cycle_layouts = {
      default = { "diff2_horizontal", "diff2_vertical" },
      merge_tool = {
        "diff3_horizontal",
        "diff3_vertical",
        "diff3_mixed",
        "diff4_mixed",
        "diff1_plain",
      },
    },

    ---@alias DiffviewInlineStyle "unified"|"overleaf"
    ---@alias DiffviewInlineDeletionHighlight "text"|"full_width"|"hanging"
    ---@class DiffviewInlineConfig
    ---@field style DiffviewInlineStyle
    ---@field deletion_highlight DiffviewInlineDeletionHighlight
    ---@field deletion_treesitter boolean
    ---@field fold_unchanged boolean

    ---@class DiffviewInlineConfig.user
    ---@field style? DiffviewInlineStyle Rendering style for `diff1_inline`. "unified" shows old lines as virt_lines above; "overleaf" renders deletions as inline strikethrough virt_text.
    ---@field deletion_highlight? DiffviewInlineDeletionHighlight Extent of the `DiffDelete` background on deleted virt_lines: `"text"` covers only the deleted chars, `"full_width"` pads to the row, `"hanging"` covers everything except the leading indent.
    ---@field deletion_treesitter? boolean Layer tree-sitter syntax highlights over the deleted virt_lines so they read like the rest of the buffer. Falls back transparently when no parser is attached.
    ---@field fold_unchanged? boolean Fold unchanged regions in `diff1_inline`, using the context from 'diffopt'.
    -- Options specific to the `diff1_inline` layout.
    inline = {
      -- Rendering style. "unified": proper unified diff -- old lines shown
      -- above modifications as virt_lines, added chars highlighted in place.
      -- "overleaf": deleted chars on modified lines rendered inline as
      -- strikethrough virtual text (Overleaf-editor style); no block echo.
      style = "unified",
      -- How far the `DiffDelete` background extends on deleted virt_lines:
      --   "text":       just the deleted characters.
      --   "full_width": highlight the row, which matches `diff2_horizontal`'s
      --                 native look.
      --   "hanging":    skip the leading indent, then highlight the rest of
      --                 the row.
      deletion_highlight = "text",
      -- Layer tree-sitter syntax highlights over the deleted virt_lines so
      -- they read like the rest of the buffer. No-op when no parser is
      -- attached for the buffer's filetype.
      deletion_treesitter = true,
      -- Fold unchanged regions with 'foldmethod' set to "expr". The number
      -- of visible context lines follows the `context:N` value in 'diffopt'.
      fold_unchanged = false,
    },
  },

  ---@alias DiffviewSortFile fun(a_name: string, b_name: string, a_data: any?, b_data: any?): boolean
  ---@alias DiffviewListingStyle "tree"|"list"
  ---@alias DiffviewMarkPlacement "inline"|"sign_column"
  ---@class DiffviewFilePanelConfig
  ---@field listing_style DiffviewListingStyle
  ---@field sort_file? DiffviewSortFile
  ---@field tree_options DiffviewTreeOptions
  ---@field list_options DiffviewListOptions
  ---@field win_config DiffviewFilePanelWinConfig
  ---@field show boolean
  ---@field always_show_sections boolean
  ---@field always_show_marks boolean
  ---@field mark_placement DiffviewMarkPlacement
  ---@field show_branch_name boolean

  ---@class DiffviewFilePanelConfig.user
  ---@field listing_style? DiffviewListingStyle "list" or "tree".
  ---@field sort_file? DiffviewSortFile Custom file comparator.
  ---@field tree_options? DiffviewTreeOptions.user Only applies when `listing_style` is "tree".
  ---@field list_options? DiffviewListOptions.user Only applies when `listing_style` is "list".
  ---@field win_config? DiffviewFilePanelWinConfig.user File panel window config.
  ---@field show? boolean Show the file panel when opening Diffview.
  ---@field always_show_sections? boolean Always show Changes and Staged sections even when empty.
  ---@field always_show_marks? boolean Show selection marks even when no files are selected.
  ---@field mark_placement? DiffviewMarkPlacement Where to render selection marks.
  ---@field show_branch_name? boolean Show branch name in the file panel header.
  file_panel = {
    listing_style = "tree",
    sort_file = nil, -- Custom file comparator: function(a_name, b_name, a_data, b_data) -> boolean

    ---@alias DiffviewFolderStatuses "never"|"only_folded"|"always"
    ---@alias DiffviewFolderCountStyle "grouped"|"simple"|"none"
    ---@class DiffviewTreeOptions
    ---@field flatten_dirs boolean
    ---@field folder_statuses DiffviewFolderStatuses
    ---@field folder_count_style DiffviewFolderCountStyle
    ---@field folder_trailing_slash boolean

    ---@class DiffviewTreeOptions.user
    ---@field flatten_dirs? boolean Flatten dirs that only contain one single dir.
    ---@field folder_statuses? DiffviewFolderStatuses When to show folder status counts.
    ---@field folder_count_style? DiffviewFolderCountStyle How to render folder counts ("grouped", "simple", "none").
    ---@field folder_trailing_slash? boolean Append "/" to folder names in the file tree.
    tree_options = {
      flatten_dirs = true,
      folder_statuses = "only_folded",
      folder_count_style = "grouped", -- "grouped" (e.g. "2M 1D"), "simple" (e.g. "3"), or "none".
      folder_trailing_slash = true, -- Append "/" to folder names in the file tree.
    },

    ---@alias DiffviewPathStyle "basename"|"full"
    ---@class DiffviewListOptions
    ---@field path_style DiffviewPathStyle

    ---@class DiffviewListOptions.user
    ---@field path_style? DiffviewPathStyle "basename" (name + dimmed path) or "full" (uniform highlight).
    list_options = {
      path_style = "basename", -- "basename" (name + dimmed path) or "full" (full path, uniform highlight).
    },

    ---@alias DiffviewFilePanelWinConfig PanelConfig.user|fun(): PanelConfig.user
    ---@alias DiffviewFilePanelWinConfig.user PanelConfig.user|fun(): PanelConfig.user
    win_config = {
      position = "left",
      width = 35,
      win_opts = {},
    },
    show = true, -- Show the file panel by default when opening Diffview.
    always_show_sections = false, -- Always show Changes and Staged changes sections even when empty.
    always_show_marks = false, -- Show selection marks even when no files are selected.
    mark_placement = "inline", -- Where to show selection marks: "inline" (next to file names) or "sign_column" (in the sign column).
    show_branch_name = false, -- Show branch name in the file panel header.
  },

  ---@alias DiffviewStatStyle "number"|"bar"|"both"
  ---@alias DiffviewSubjectHighlight "ref_aware"|"merge_aware"|"plain"
  ---@alias DiffviewCommitFormatField "status"|"files"|"stats"|"hash"|"reflog"|"ref"|"subject"|"author"|"date"
  ---@alias DiffviewDateFormat "auto"|"relative"|"iso"
  ---@class DiffviewFileHistoryPanelConfig
  ---@field stat_style DiffviewStatStyle
  ---@field subject_highlight DiffviewSubjectHighlight
  ---@field commit_format DiffviewCommitFormatField[]
  ---@field log_options DiffviewFileHistoryLogOptions
  ---@field win_config DiffviewFileHistoryPanelWinConfig
  ---@field show boolean
  ---@field commit_subject_max_length integer
  ---@field date_format DiffviewDateFormat

  ---@class DiffviewFileHistoryPanelConfig.user
  ---@field stat_style? DiffviewStatStyle "number", "bar", or "both".
  ---@field subject_highlight? DiffviewSubjectHighlight "ref_aware" colours by pushed/unpushed; "merge_aware" adds a third colour for commits reachable from a main/master branch; "plain" is uniform.
  ---@field commit_format? DiffviewCommitFormatField[] Ordered components shown per commit entry.
  ---@field log_options? DiffviewFileHistoryLogOptions.user Log options per adapter. See `|diffview-config-log_options|`.
  ---@field win_config? DiffviewFileHistoryPanelWinConfig.user File history panel window config.
  ---@field show? boolean Show the file history panel when opening DiffviewFileHistory.
  ---@field commit_subject_max_length? integer Max length for commit subject display.
  ---@field date_format? DiffviewDateFormat "auto", "relative", or "iso".
  file_history_panel = {
    stat_style = "number", -- "number" (e.g. "5, 3"), "bar" (e.g. "| 8 +++++---"), or "both".
    subject_highlight = "ref_aware", -- "ref_aware" (pushed vs unpushed), "merge_aware" (adds a third colour for merged-to-main/master), or "plain".
    -- Ordered list of components to show for each commit entry.
    -- Available: "status", "files", "stats", "hash", "reflog", "ref", "subject", "author", "date"
    commit_format = {
      "status",
      "files",
      "stats",
      "hash",
      "reflog",
      "ref",
      "subject",
      "author",
      "date",
    },

    ---@class DiffviewFileHistoryLogOptions
    ---@field git ConfigLogOptions
    ---@field hg ConfigLogOptions
    ---@field jj ConfigLogOptions
    ---@field p4 ConfigLogOptions

    ---@class DiffviewFileHistoryLogOptions.user
    ---@field git? ConfigLogOptions.user Log options for git.
    ---@field hg? ConfigLogOptions.user Log options for hg.
    ---@field jj? ConfigLogOptions.user Log options for Jujutsu.
    ---@field p4? ConfigLogOptions.user Log options for Perforce.

    ---@class ConfigLogOptions
    ---@field single_file LogOptions
    ---@field multi_file LogOptions

    ---@class ConfigLogOptions.user
    ---@field single_file? LogOptions.user
    ---@field multi_file? LogOptions.user
    log_options = {
      ---@type ConfigLogOptions.user
      git = {
        single_file = {
          diff_merges = "first-parent",
          follow = true,
        },
        multi_file = {
          diff_merges = "first-parent",
        },
      },
      ---@type ConfigLogOptions.user
      hg = {
        single_file = {},
        multi_file = {},
      },
      ---@type ConfigLogOptions.user
      jj = {
        single_file = {},
        multi_file = {},
      },
      ---@type ConfigLogOptions.user
      p4 = {
        single_file = {},
        multi_file = {},
      },
    },

    ---@alias DiffviewFileHistoryPanelWinConfig PanelConfig.user|fun(): PanelConfig.user
    ---@alias DiffviewFileHistoryPanelWinConfig.user PanelConfig.user|fun(): PanelConfig.user
    win_config = {
      position = "bottom",
      height = 16,
      win_opts = {},
    },
    show = true, -- Show the file history panel by default when opening DiffviewFileHistory.
    commit_subject_max_length = 72, -- Max length for commit subject display.
    date_format = "auto", -- Date format: "auto" (relative for recent, ISO for old), "relative", or "iso".
  },

  ---@class DiffviewCommitLogPanelConfig
  ---@field win_config DiffviewCommitLogPanelWinConfig

  ---@class DiffviewCommitLogPanelConfig.user
  ---@field win_config? DiffviewCommitLogPanelWinConfig.user Commit log panel window config.
  commit_log_panel = {
    ---@alias DiffviewCommitLogPanelWinConfig PanelConfig.user|fun(): PanelConfig.user
    ---@alias DiffviewCommitLogPanelWinConfig.user PanelConfig.user|fun(): PanelConfig.user
    win_config = {
      win_opts = {},
    },
  },

  ---@class DiffviewDefaultArgs
  ---@field DiffviewOpen string[]
  ---@field DiffviewFileHistory string[]

  ---@class DiffviewDefaultArgs.user
  ---@field DiffviewOpen? string[] Default args prepended to `:DiffviewOpen`.
  ---@field DiffviewFileHistory? string[] Default args prepended to `:DiffviewFileHistory`.
  default_args = {
    DiffviewOpen = {},
    DiffviewFileHistory = {},
  },

  ---@class DiffviewDiffBufCtx
  ---@field symbol string Layout-window symbol ("a"|"b"|"c"|"d").
  ---@field layout_name string Concrete layout, e.g. "diff2_horizontal".

  ---@class DiffviewHooks
  ---@field view_opened? fun(view: View)
  ---@field view_closed? fun(view: View)
  ---@field view_enter? fun(view: View)
  ---@field view_leave? fun(view: View)
  ---@field view_post_layout? fun(view: View)
  ---@field diff_buf_read? fun(bufnr: integer, ctx: DiffviewDiffBufCtx)
  ---@field diff_buf_win_enter? fun(bufnr: integer, winid: integer, ctx: DiffviewDiffBufCtx)
  ---@field selection_changed? fun(view: DiffView)
  ---@field files_staged? fun(view: DiffView)
  ---@field [string] fun(...): any?
  hooks = {},

  ---@class DiffviewKeymapsConfig
  ---@field preset "minimal"|"none"
  ---@field interaction "mouse"|"hybrid"|"keyboard"
  ---@field view DiffviewKeymapEntry[]
  ---@field diff1 DiffviewKeymapEntry[]
  ---@field diff1_inline DiffviewKeymapEntry[]
  ---@field diff2 DiffviewKeymapEntry[]
  ---@field diff3 DiffviewKeymapEntry[]
  ---@field diff4 DiffviewKeymapEntry[]
  ---@field file_panel DiffviewKeymapEntry[]
  ---@field file_history_panel DiffviewKeymapEntry[]
  ---@field option_panel DiffviewKeymapEntry[]
  ---@field help_panel DiffviewKeymapEntry[]
  ---@field commit_log_panel DiffviewKeymapEntry[]

  ---@class DiffviewKeymapsConfig.user
  ---@field preset? "minimal"|"none"
  ---@field interaction? "mouse"|"hybrid"|"keyboard"
  ---@field view? DiffviewKeymapEntry[]
  ---@field diff1? DiffviewKeymapEntry[]
  ---@field diff1_inline? DiffviewKeymapEntry[]
  ---@field diff2? DiffviewKeymapEntry[]
  ---@field diff3? DiffviewKeymapEntry[]
  ---@field diff4? DiffviewKeymapEntry[]
  ---@field file_panel? DiffviewKeymapEntry[]
  ---@field file_history_panel? DiffviewKeymapEntry[]
  ---@field option_panel? DiffviewKeymapEntry[]
  ---@field help_panel? DiffviewKeymapEntry[]
  ---@field commit_log_panel? DiffviewKeymapEntry[]
  -- Tabularize formatting pattern: `\v(\"[^"]{-}\",\ze(\s*)actions)|actions\.\w+(\(.{-}\))?,?|\{\ desc\ \=`
  keymaps = {
    preset = "minimal",
    interaction = "hybrid",
    view = {},
    diff1 = {},
    diff1_inline = {},
    diff2 = {},
    diff3 = {},
    diff4 = {},
    file_panel = {
      { "n", "<cr>", "navigation.select_entry" },
      { "n", "<LeftMouse>", "navigation.select_entry" },
      { "n", "?", "view.action_palette" },
    },
    file_history_panel = {
      { "n", "<cr>", "navigation.select_entry" },
      { "n", "<LeftMouse>", "navigation.select_entry" },
      { "n", "?", "view.action_palette" },
    },
    option_panel = {
      { "n", "<cr>", "navigation.select_entry" },
      { "n", "q", "view.close" },
      { "n", "<esc>", "view.close" },
      { "n", "?", "view.action_palette" },
    },
    help_panel = {
      { "n", "q", "view.close" },
      { "n", "<esc>", "view.close" },
    },
    commit_log_panel = {
      { "n", "q", "view.close" },
      { "n", "<esc>", "view.close" },
    },
  },
}

return M.defaults
