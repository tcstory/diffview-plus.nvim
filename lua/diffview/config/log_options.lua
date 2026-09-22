---File-history log option schemas and defaults.

local M = {}

---@class GitLogOptions
---@field follow boolean
---@field first_parent boolean
---@field show_pulls boolean
---@field reflog boolean
---@field walk_reflogs boolean
---@field all boolean
---@field merges boolean
---@field no_merges boolean
---@field reverse boolean
---@field cherry_pick boolean
---@field left_only boolean
---@field right_only boolean
---@field max_count integer
---@field L string[]
---@field author? string
---@field grep? string
---@field G? string
---@field S? string
---@field diff_merges? string
---@field rev_range? string
---@field base? string
---@field path_args string[]
---@field after? string
---@field before? string
---@field rename_threshold? integer Per-view rename similarity threshold (0-100). Overrides |diffview-config-rename_threshold| for this view.

---@class HgLogOptions
---@field follow? string
---@field limit integer
---@field user? string
---@field no_merges boolean
---@field rev? string
---@field keyword? string
---@field branch? string
---@field bookmark? string
---@field include? string
---@field exclude? string
---@field path_args string[]

---@class JjLogOptions
---@field limit integer
---@field reversed boolean
---@field revisions? string
---@field path_args string[]

---@alias LogOptions GitLogOptions|HgLogOptions|JjLogOptions

---@class GitLogOptions.user
---@field follow? boolean
---@field first_parent? boolean
---@field show_pulls? boolean
---@field reflog? boolean
---@field walk_reflogs? boolean
---@field all? boolean
---@field merges? boolean
---@field no_merges? boolean
---@field reverse? boolean
---@field cherry_pick? boolean
---@field left_only? boolean
---@field right_only? boolean
---@field max_count? integer
---@field L? string[]
---@field author? string
---@field grep? string
---@field G? string
---@field S? string
---@field diff_merges? string
---@field rev_range? string
---@field base? string
---@field path_args? string[]
---@field after? string
---@field before? string
---@field rename_threshold? integer Per-view rename similarity threshold (0-100). Overrides |diffview-config-rename_threshold| for this view.

---@class HgLogOptions.user
---@field follow? string
---@field limit? integer
---@field user? string
---@field no_merges? boolean
---@field rev? string
---@field keyword? string
---@field branch? string
---@field bookmark? string
---@field include? string
---@field exclude? string
---@field path_args? string[]

---@class JjLogOptions.user
---@field limit? integer
---@field reversed? boolean
---@field revisions? string
---@field path_args? string[]

---@alias LogOptions.user GitLogOptions.user|HgLogOptions.user|JjLogOptions.user

M.log_option_defaults = {
  ---@type GitLogOptions
  git = {
    follow = false,
    first_parent = false,
    show_pulls = false,
    reflog = false,
    walk_reflogs = false,
    all = false,
    merges = false,
    no_merges = false,
    reverse = false,
    cherry_pick = false,
    left_only = false,
    right_only = false,
    rev_range = nil,
    base = nil,
    max_count = 256,
    L = {},
    diff_merges = nil,
    author = nil,
    grep = nil,
    G = nil,
    S = nil,
    path_args = {},
    rename_threshold = nil,
  },
  ---@type HgLogOptions
  hg = {
    limit = 256,
    user = nil,
    no_merges = false,
    rev = nil,
    keyword = nil,
    include = nil,
    exclude = nil,
    path_args = {},
  },
  ---@type JjLogOptions
  jj = {
    limit = 256,
    reversed = false,
    revisions = nil,
    path_args = {},
  },
  ---@type HgLogOptions # P4 reuses the `HgLogOptions` schema; see `P4Adapter.config_key`.
  p4 = {
    limit = 256,
    user = nil,
    no_merges = false,
    rev = nil,
    keyword = nil,
    include = nil,
    exclude = nil,
    path_args = {},
  },
}

return M.log_option_defaults
