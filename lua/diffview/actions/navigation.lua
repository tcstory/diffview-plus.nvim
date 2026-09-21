return function(M, R)
  local C = R.category.NAVIGATION
  local specs = {
    { "navigation.next_entry", "Next entry", "Move to the next file entry.", "next_entry" },
    { "navigation.prev_entry", "Previous entry", "Move to the previous file entry.", "prev_entry" },
    {
      "navigation.next_entry_in_commit",
      "Next entry in commit",
      "Move to the next entry in this commit.",
      "next_entry_in_commit",
    },
    {
      "navigation.prev_entry_in_commit",
      "Previous entry in commit",
      "Move to the previous entry in this commit.",
      "prev_entry_in_commit",
    },
    { "navigation.select_entry", "Select entry", "Open the focused entry.", "select_entry" },
    {
      "navigation.select_next_entry",
      "Select next entry",
      "Open the next entry.",
      "select_next_entry",
    },
    {
      "navigation.select_prev_entry",
      "Select previous entry",
      "Open the previous entry.",
      "select_prev_entry",
    },
    {
      "navigation.select_first_entry",
      "Select first entry",
      "Open the first entry.",
      "select_first_entry",
    },
    {
      "navigation.select_last_entry",
      "Select last entry",
      "Open the last entry.",
      "select_last_entry",
    },
    {
      "navigation.select_next_commit",
      "Select next commit",
      "Open the next commit.",
      "select_next_commit",
    },
    {
      "navigation.select_prev_commit",
      "Select previous commit",
      "Open the previous commit.",
      "select_prev_commit",
    },
    { "navigation.focus_entry", "Focus entry", "Focus the current diff entry.", "focus_entry" },
    { "navigation.focus_files", "Focus files", "Focus the files panel.", "focus_files" },
    {
      "navigation.next_inline_hunk",
      "Next inline hunk",
      "Jump to the next inline-diff hunk.",
      "next_inline_hunk",
    },
    {
      "navigation.prev_inline_hunk",
      "Previous inline hunk",
      "Jump to the previous inline-diff hunk.",
      "prev_inline_hunk",
    },
  }
  for _, spec in ipairs(specs) do
    R.direct(spec[1], spec[2], spec[3], C, spec[4])
  end
  local available = R.contextual(function(v)
    return M._is_applicable(M.next_conflict, v)
  end, "No merge conflict is active")
  R.direct(
    "navigation.next_conflict",
    "Next conflict",
    "Jump to the next merge conflict.",
    C,
    "next_conflict",
    available
  )
  R.direct(
    "navigation.prev_conflict",
    "Previous conflict",
    "Jump to the previous merge conflict.",
    C,
    "prev_conflict",
    available
  )
end
