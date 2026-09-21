return function(_, R)
  local C = R.category.VIEW
  local specs = {
    { "view.close", "Close", "Close the current view or temporary panel.", "close" },
    { "view.open_all_folds", "Open all folds", "Open all panel folds.", "open_all_folds" },
    { "view.close_all_folds", "Close all folds", "Close all panel folds.", "close_all_folds" },
    { "view.open_fold", "Open fold", "Open the fold under the cursor.", "open_fold" },
    { "view.close_fold", "Close fold", "Close the fold under the cursor.", "close_fold" },
    { "view.toggle_fold", "Toggle fold", "Toggle the fold under the cursor.", "toggle_fold" },
  }
  for _, spec in ipairs(specs) do
    R.direct(spec[1], spec[2], spec[3], C, spec[4])
  end
  require("diffview.runtime.action_registry").register({
    id = "view.action_palette",
    label = "Actions",
    desc = "Open the context-sensitive action palette.",
    category = C,
    execute = function()
      require("diffview.ui.action_palette").open()
    end,
    surfaces = { "toolbar" },
  })
end
