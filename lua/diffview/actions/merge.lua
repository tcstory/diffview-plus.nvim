return function(M, R)
  local C = R.category.MERGE
  local available = R.contextual(function(v)
    return v ~= nil and (v.merge_ctx ~= nil or v.merge_session ~= nil)
  end, "No merge session is active")
  R.direct(
    "merge.merge_mark_resolved",
    "Mark resolved",
    "Mark the current file resolved.",
    C,
    "merge_mark_resolved",
    available
  )
  R.direct(
    "merge.merge_apply",
    "Apply merge",
    "Apply all merge results.",
    C,
    "merge_apply",
    available,
    {
      danger = true,
      confirm = "Apply all resolved merge results to the working tree?",
    }
  )
  for _, target in ipairs({ "ours", "theirs", "base", "all", "none" }) do
    local upper = target:upper()
    R.factory(
      "merge.choose_" .. target,
      "Choose " .. upper,
      "Resolve this conflict with " .. upper .. ".",
      C,
      function()
        return M.conflict_choose(target)
      end,
      available
    )
    R.factory(
      "merge.choose_all_" .. target,
      "Choose all " .. upper,
      "Resolve this file with " .. upper .. ".",
      C,
      function()
        return M.conflict_choose_all(target)
      end,
      available,
      { danger = true, confirm = "Resolve every conflict in this file with " .. upper .. "?" }
    )
  end
  for _, target in ipairs({ "ours", "theirs", "base" }) do
    local upper = target:upper()
    R.factory(
      "merge.choose_side_" .. target,
      "Use entire " .. upper,
      "Replace the result with the complete " .. upper .. " side.",
      C,
      function()
        return M.conflict_choose_side(target)
      end,
      available,
      { danger = true, confirm = "Replace the complete merge result with " .. upper .. "?" }
    )
  end
end
