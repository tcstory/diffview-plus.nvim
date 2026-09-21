return function(_, R)
  local Capability = require("diffview.vcs.capability").Capability
  local Command = require("diffview.scene.views.diff.command")
  local C = R.category.FILE
  local specs = {
    { "file.goto_file", "Go to file", "Open the current file.", "goto_file" },
    { "file.goto_file_edit", "Edit file", "Edit the current file.", "goto_file_edit" },
    {
      "file.goto_file_edit_close",
      "Edit file and close",
      "Edit the current file and close Diffview.",
      "goto_file_edit_close",
    },
    {
      "file.goto_file_split",
      "Open in split",
      "Open the current file in a split.",
      "goto_file_split",
    },
    { "file.goto_file_tab", "Open in tab", "Open the current file in a tab.", "goto_file_tab" },
    {
      "file.open_file_external",
      "Open externally",
      "Open the current file in the system application.",
      "open_file_external",
    },
    {
      "file.open_in_new_tab",
      "Open view in tab",
      "Open this Diffview in a new tab.",
      "open_in_new_tab",
    },
    {
      "file.open_commit_in_browser",
      "Open commit in browser",
      "Open the selected commit in a browser.",
      "open_commit_in_browser",
    },
    { "file.open_commit_log", "Commit log", "Show commit details.", "open_commit_log" },
    {
      "file.open_commit_log_file",
      "File commit log",
      "Show commit details for this file.",
      "open_commit_log_file",
    },
    { "file.toggle_untracked", "Toggle untracked", "Toggle untracked files.", "toggle_untracked" },
  }
  for _, spec in ipairs(specs) do
    R.direct(spec[1], spec[2], spec[3], C, spec[4])
  end
  R.command(
    "file.refresh_files",
    "Refresh files",
    "Refresh files and statistics.",
    C,
    Command.Type.REFRESH
  )
  R.command(
    "file.filter_files",
    "Filter files",
    "Filter the file panel by path.",
    C,
    Command.Type.FILTER
  )
  R.command(
    "file.toggle_flatten_dirs",
    "Flatten directories",
    "Toggle flattened directories.",
    C,
    Command.Type.FLATTEN_DIRS
  )
  R.command(
    "file.listing_style",
    "Listing style",
    "Cycle the file listing style.",
    C,
    Command.Type.LISTING_STYLE
  )
  R.command(
    "file.restore_entry",
    "Restore entry",
    "Restore the selected entry.",
    C,
    Command.Type.RESTORE,
    R.contextual(function(view)
      return view and view.adapter and view.adapter:supports(Capability.RESTORE)
    end, "The current VCS adapter cannot restore files"),
    {
      danger = true,
      confirm = "Restore the selected entry? This can overwrite working-tree changes.",
    }
  )
end
