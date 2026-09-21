return function(M, R)
  local C = R.category.DIFF
  R.direct(
    "diff.diff_against_default_branch",
    "Diff default branch",
    "Compare the working tree with the default branch.",
    C,
    "diff_against_default_branch"
  )
  R.direct(
    "diff.diffget_inline",
    "Diffget inline",
    "Revert the current inline hunk.",
    C,
    "diffget_inline"
  )
  local stage = R.contextual(function(v)
    return M._is_applicable(M.stage_all, v)
  end, "This view has no stageable working tree")
  local toggle = R.contextual(function(v)
    return M._is_applicable(M.toggle_stage_entry, v)
  end, "The selected entry cannot be staged or resolved here")
  R.direct("diff.stage_all", "Stage all", "Stage all entries.", C, "stage_all", stage)
  R.direct("diff.unstage_all", "Unstage all", "Unstage all entries.", C, "unstage_all", stage)
  R.direct(
    "diff.toggle_stage_entry",
    "Toggle stage",
    "Stage or unstage the selected entry.",
    C,
    "toggle_stage_entry",
    toggle
  )
  R.direct(
    "diff.toggle_select_entry",
    "Toggle selection",
    "Toggle selection of the focused entry.",
    C,
    "toggle_select_entry"
  )
  R.direct(
    "diff.clear_select_entries",
    "Clear selections",
    "Clear all file selections.",
    C,
    "clear_select_entries"
  )
  R.direct(
    "diff.toggle_hide_selected",
    "Hide reviewed",
    "Toggle hiding selected files.",
    C,
    "toggle_hide_selected"
  )
  for _, target in ipairs({ "ours", "theirs", "base", "local" }) do
    local upper = target:upper()
    R.factory(
      "diff.get_" .. target,
      "Diffget " .. upper,
      "Obtain the current hunk from " .. upper .. ".",
      C,
      function()
        return M.diffget(target)
      end
    )
    R.factory(
      "diff.put_" .. target,
      "Diffput " .. upper,
      "Send the current hunk to " .. upper .. ".",
      C,
      function()
        return M.diffput(target)
      end
    )
  end
end
