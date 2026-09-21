return function(M, R)
  local Capability = require("diffview.vcs.capability").Capability
  local Command = require("diffview.scene.views.diff.command")
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
    return v
      and v.adapter
      and v.adapter:supports(Capability.STAGE)
      and M._is_applicable(M.stage_all, v)
  end, "This view has no stageable working tree")
  local toggle = R.contextual(function(v)
    return v
      and v.adapter
      and v.adapter:supports(Capability.STAGE)
      and M._is_applicable(M.toggle_stage_entry, v)
  end, "The selected entry cannot be staged or resolved here")
  R.command("diff.stage_all", "Stage all", "Stage all entries.", C, Command.Type.STAGE_ALL, stage)
  R.command(
    "diff.unstage_all",
    "Unstage all",
    "Unstage all entries.",
    C,
    Command.Type.UNSTAGE_ALL,
    stage
  )
  R.command(
    "diff.toggle_stage_entry",
    "Toggle stage",
    "Stage or unstage the selected entry.",
    C,
    Command.Type.TOGGLE_STAGE,
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
  R.command(
    "diff.toggle_hide_selected",
    "Hide reviewed",
    "Toggle hiding selected files.",
    C,
    Command.Type.HIDE_REVIEWED
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
