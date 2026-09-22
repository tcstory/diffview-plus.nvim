return function(_, R)
  local C = R.category.HISTORY
  local function history_view(view)
    return view and view.panel and view.panel.store and view.panel.option_panel ~= nil
  end
  local in_history = R.contextual(history_view, "No file-history view is active")
  local query_running = R.contextual(function(view)
    return history_view(view) and view.panel.store.query.status == "streaming"
  end, "No history query is running")
  R.direct(
    "file.open_in_diffview",
    "Open in Diffview",
    "Open the history entry in a Diffview.",
    C,
    "open_in_diffview"
  )
  R.direct(
    "file.copy_hash",
    "Copy hash",
    "Copy the selected commit hash.",
    C,
    "copy_hash",
    in_history
  )
  R.direct(
    "diff.diff_against_head",
    "Diff against HEAD",
    "Compare the selected commit with HEAD.",
    C,
    "diff_against_head",
    in_history
  )
  R.direct(
    "layout.options",
    "History options",
    "Open file-history filter options.",
    C,
    "options",
    in_history
  )
  R.direct(
    "history.filter",
    "History filters",
    "Open the clickable file-history filters.",
    C,
    "filter_history",
    in_history,
    { surfaces = { "toolbar", "context" } }
  )
  R.direct(
    "history.cancel_query",
    "Cancel history query",
    "Cancel the active streaming history query.",
    C,
    "cancel_history_query",
    query_running,
    { surfaces = { "toolbar", "context" } }
  )
end
