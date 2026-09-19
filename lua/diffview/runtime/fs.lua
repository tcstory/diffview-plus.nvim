--- runtime/fs.lua
---
--- Responsibility:  File-system helpers that prefer `vim.fs` (0.12 stable)
---                  and fall back to `vim.uv` only for operations that have
---                  no `vim.fs` equivalent.
--- Input:           Path strings (POSIX or Windows normalised by vim.fs).
--- Output:          Path strings, booleans, or file metadata tables.
--- Owns:            Nothing — all operations are stateless.
--- Does NOT own:    The PathLib class (`path.lua`); that module contains
---                  many more operations and is being analysed separately
---                  (see docs/deletion_ledger.md investigation queue).
---                  This module exposes only the operations required by the
---                  new runtime and VCS adapter code.
---
--- Neovim API used:
---   :h vim.fs.normalize()   — normalise a path (expand ~, resolve separators)
---   :h vim.fs.joinpath()    — join path segments safely
---   :h vim.fs.dirname()     — parent directory of a path
---   :h vim.fs.basename()    — last component of a path
---   :h vim.fs.root()        — walk up to find root for a pattern/predicate
---   :h vim.fs.relpath()     — compute a relative path (0.12+)
---   :h vim.uv.fs_stat()     — stat a path (type, size, mtime…)
---   :h vim.uv.fs_access()   — test access permissions
---   :h vim.uv               — only for operations without a vim.fs equivalent
---
--- Why this module exists:
---   The legacy `path.lua` (PathLib) was written before `vim.fs` existed.
---   New code should prefer `vim.fs`; this module documents that preference
---   and provides consistent wrappers for the handful of uv calls that are
---   still needed.

local uv = vim.uv

local M = {}

--- Normalise `path`: expand `~`, resolve `.` and `..`, unify separators.
--- :h vim.fs.normalize
---@param path string
---@return string
function M.normalize(path)
  return vim.fs.normalize(path)
end

--- Join path segments.  Equivalent to `os.path.join` in Python.
--- :h vim.fs.joinpath
---@param ... string
---@return string
function M.join(...)
  return vim.fs.joinpath(...)
end

--- Return the parent directory of `path`.
--- :h vim.fs.dirname
---@param path string
---@return string
function M.dirname(path)
  return vim.fs.dirname(path) or path
end

--- Return the last component of `path` (file name + extension).
--- :h vim.fs.basename
---@param path string
---@return string
function M.basename(path)
  return vim.fs.basename(path)
end

--- Walk from `path` upward until a directory or file matching `marker` is
--- found.  Returns the directory that contains `marker`, or nil.
---
--- `marker` may be:
---   - a string: the exact file/directory name to look for (e.g., ".git")
---   - a string[]: look for any of the listed names
---   - a function(name, path) → boolean: custom predicate
---
--- :h vim.fs.root
---@param path string   Starting path (file or directory).
---@param marker string|string[]|fun(name:string, path:string):boolean
---@return string?
function M.find_root(path, marker)
  return vim.fs.root(path, marker)
end

--- Compute the path of `target` relative to `base`.
--- Returns nil when `target` is on a different Windows drive.
--- :h vim.fs.relpath  (available in Neovim 0.12+)
---@param base string
---@param target string
---@return string?
function M.relpath(base, target)
  return vim.fs.relpath(base, target)
end

--- Return a `uv.fs_stat` result table for `path`, or nil if it does not exist.
--- Callers must not hold the stat across yield points — the file may change.
---
--- :h vim.uv.fs_stat
---@param path string
---@return uv.aliases.fs_stat_table?
function M.stat(path)
  -- uv.fs_stat returns (stat, err_msg, err_name); we ignore errors and
  -- treat them as "not found".
  local ok, _ = uv.fs_stat(path)
  return ok
end

--- Return true if `path` exists (any type: file, directory, symlink, …).
---@param path string
---@return boolean
function M.exists(path)
  return M.stat(path) ~= nil
end

--- Return the type of `path` as a string, or nil if it does not exist.
--- Possible values: "file", "directory", "link", "char", "block",
---                  "fifo", "socket", "unknown".
---@param path string
---@return string?
function M.filetype(path)
  local s = M.stat(path)
  return s and s.type
end

--- Return true if `path` is a regular file.
---@param path string
---@return boolean
function M.is_file(path)
  return M.filetype(path) == "file"
end

--- Return true if `path` is a directory.
---@param path string
---@return boolean
function M.is_dir(path)
  return M.filetype(path) == "directory"
end

--- Return true if the current user can read `path`.
---
--- :h vim.uv.fs_access  — checks access with a POSIX mode string ("R", "W", "X").
---@param path string
---@return boolean
function M.readable(path)
  -- uv.fs_access(path, mode) returns true/false (no coroutine needed).
  return uv.fs_access(path, "R") == true
end

--- Return the current working directory.
---
--- :h vim.uv.cwd  — no vim.fs equivalent; must use uv directly.
---@return string
function M.cwd()
  return uv.cwd() or ""
end

return M
