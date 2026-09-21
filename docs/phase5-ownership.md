# Phase 5: view, layout, and buffer ownership

Phase 5 moves editor-resource ownership out of the inherited scene classes and
into small composable objects. The existing `View`, `Layout`, and `Window`
classes remain as dispatch facades for concrete views and layouts, but no
longer define the ownership contract.

## Components

- `ViewShell` owns the view lifecycle and gates every registered action while
  a view is loading or closing. It also releases resources registered with the
  shell when the view closes.
- `LayoutSpec` owns a defensive copy of the named slots, creation commands,
  order, and constraints. `LayoutEngine` is the only window creation/reuse
  path used by `Layout:create_wins`.
- `BufferLease` snapshots only the buffer options, keymaps, diagnostics, and
  inlay-hint state it changes. Releasing it restores the exact prior state,
  including an already-disabled feature.
- `WindowLease` captures the displayed buffer, window-local options, cursor,
  viewport, and folds through `winsaveview()` / `winrestview()`.

`StandardView` stores a lease snapshot per layout class. An A → B → A switch
therefore restores every matching slot and its focused window; the
`FileEntry` and its `vcs.File` producers are never copied or replaced by that
state restoration.

## Neovim APIs

- `nvim_buf_get_keymap()` and `vim.keymap.set()` preserve callback and string
  mappings without inventing a second keymap format.
- `vim.diagnostic.is_enabled()` and `vim.lsp.inlay_hint.is_enabled()` capture
  the prior state before disabling a feature.
- `winsaveview()` and `winrestview()` carry cursor, viewport, and fold state as
  one Neovim-owned value.
- `nvim_win_is_valid()` is checked at every lease boundary because layout
  changes and user autocmds can invalidate a window synchronously.

## Removed workaround

The shared null buffer no longer installs `<Nop>` mappings for `do`, `dp`, or
merge-side variants. Those mappings were domain policy attached to a sentinel
buffer and could overwrite user buffer-local state. Interactive commands now
enter through `ActionRegistry`, whose availability check delegates to the
current `ViewShell`.

The custom OOP implementation itself is deleted in Phase 10 after the
remaining scene and adapter facades have migrated; extending it is prohibited
from this phase onward.
