---Git merge queries. Returns domain data or structured QueryResult values.

local path_args = require("diffview.vcs.path_args")
local query = require("diffview.vcs.query")

local M = {}

---@param adapter GitAdapter
---@return vcs.MergeContext?
function M.context(adapter)
  local their_head
  for _, name in ipairs({ "MERGE_HEAD", "REBASE_HEAD", "REVERT_HEAD", "CHERRY_PICK_HEAD" }) do
    if vim.uv.fs_stat(vim.fs.joinpath(adapter.ctx.dir, name)) then
      their_head = name
      break
    end
  end
  if not their_head then
    return nil
  end

  local ret = {}
  local out, code = adapter:exec_sync(
    { "show", "-s", "--no-show-signature", "--pretty=format:%H%n%D", "HEAD", "--" },
    adapter.ctx.toplevel
  )
  ret.ours = code ~= 0 and {} or { hash = out[1], ref_names = out[2] }

  out, code = adapter:exec_sync(
    { "show", "-s", "--no-show-signature", "--pretty=format:%H%n%D", their_head, "--" },
    adapter.ctx.toplevel
  )
  ret.theirs = code ~= 0 and {} or { hash = out[1], ref_names = out[2] }

  out, code = adapter:exec_sync({ "merge-base", "HEAD", their_head }, adapter.ctx.toplevel)
  if code ~= 0 then
    ret.base = { hash = adapter.Rev.NULL_TREE_SHA, ref_names = nil }
  else
    ret.base = {
      hash = out[1],
      ref_names = adapter:exec_sync(
        { "show", "-s", "--no-show-signature", "--pretty=format:%D", out[1] },
        adapter.ctx.toplevel
      )[1],
    }
  end
  return ret
end

---@param adapter GitAdapter
---@param paths string[]?
---@param token? vcs.CancellationToken
---@return vcs.QueryResult
function M.conflicted_files(adapter, paths, token)
  local context = { adapter = "git", operation = "merge.conflicted_files" }
  local cancelled = query.cancelled(token, context)
  if cancelled then
    return cancelled
  end
  local args = path_args.append({ "diff", "--name-only", "--diff-filter=U" }, paths)
  local result = adapter:query(args, { operation = context.operation, token = token })
  if not result.ok then
    return result
  end
  return query.ok(result.value.stdout)
end

return M
