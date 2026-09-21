return function(M, R)
  local C = R.category.LAYOUT
  R.direct(
    "layout.cycle_layout",
    "Cycle layout",
    "Cycle through available layouts.",
    C,
    "cycle_layout"
  )
  R.direct("layout.toggle_files", "Toggle files", "Toggle the files panel.", C, "toggle_files")
  R.factory("layout.scroll_up", "Scroll view up", "Scroll the diff workspace up.", C, function()
    return M.scroll_view(-0.25)
  end)
  R.factory("layout.scroll_down", "Scroll view down", "Scroll the diff workspace down.", C, function()
    return M.scroll_view(0.25)
  end)
  for _, name in ipairs({
    "diff1_plain",
    "diff1_inline",
    "diff2_horizontal",
    "diff2_vertical",
    "diff3_horizontal",
    "diff3_vertical",
    "diff3_mixed",
    "diff4_mixed",
  }) do
    R.factory(
      "layout.set_" .. name,
      "Layout: " .. name,
      "Switch to the " .. name .. " layout.",
      C,
      function()
        return M.set_layout(name)
      end
    )
  end
end
