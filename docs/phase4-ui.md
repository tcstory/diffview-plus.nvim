# Phase 4 developer note: component, renderer and router

Phase 4 separates UI description from Neovim resources. An immutable
`ui.component` value contains only identity, text/highlights, action ID,
disabled state, tooltip and children. The renderer owns buffer lines and
extmarks. The router owns every keyboard, mouse and winbar route and removes
them by owner when a UI closes.

```text
Component(action ID) -> Renderer(buffer + extmark patch)
         |                         |
         +------> UIRouter <-------+
                    |
                    +-> ActionRegistry -> domain action
```

The renderer compares the previous and next line arrays, preserves the common
prefix/suffix, and writes only the changed range. Highlight-only updates clear
and rebuild only affected extmark rows. Viewport-only decorations use the
Neovim 0.12 decoration provider `on_range` callback with ephemeral extmarks.

## Minimal component example

This small example shows the ownership boundary. The component describes a
button; the buffer and window display it; an extmark supplies its highlight;
the router maps both `<CR>` and its display-cell mouse span to one action ID.

```lua
local Component = require("diffview.ui.component")
local Router = require("diffview.ui.router")

local owner = {}
local button = Component.new({
  identity = "refresh",
  text = { { text = "[ Refresh ]", hl = "DiffviewFilePanelTitle" } },
  action = "file.refresh_files",
  tooltip = "Reload files from the adapter.",
})

local buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { Component.text(button) })
local window = vim.api.nvim_open_win(buffer, false, {
  relative = "editor", row = 1, col = 1, width = 14, height = 1,
})
vim.api.nvim_buf_set_extmark(buffer, vim.api.nvim_create_namespace("example"), 0, 0, {
  end_col = #Component.text(button), hl_group = "DiffviewFilePanelTitle",
})

local span = Router.segment_spans({ { text = Component.text(button) } })[1]
Router.register({
  owner = owner, action = button.action, bufnr = buffer, line = 1,
  start_col = span.start_col, end_col = span.end_col,
})
vim.keymap.set("n", "<CR>", Router.callback("keyboard", buffer), { buffer = buffer })
vim.keymap.set("n", "<LeftMouse>", Router.callback("mouse", buffer), { buffer = buffer })

-- The UI lifecycle owns cleanup.
Router.unregister_owner(owner)
vim.api.nvim_win_close(window, true)
vim.api.nvim_buf_delete(buffer, { force = true })
```

`keymaps.interaction` selects `"mouse"`, `"keyboard"`, or the default
`"hybrid"`. Persistent panels install only the activation mechanisms enabled
by that mode; action execution still goes through `UIRouter`.
