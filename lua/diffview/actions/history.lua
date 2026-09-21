return function(_, R)
  local C = R.category.HISTORY
  R.direct(
    "file.open_in_diffview",
    "Open in Diffview",
    "Open the history entry in a Diffview.",
    C,
    "open_in_diffview"
  )
  R.direct("file.copy_hash", "Copy hash", "Copy the selected commit hash.", C, "copy_hash")
  R.direct(
    "diff.diff_against_head",
    "Diff against HEAD",
    "Compare the selected commit with HEAD.",
    C,
    "diff_against_head"
  )
  R.direct("layout.options", "History options", "Open file-history filter options.", C, "options")
end
