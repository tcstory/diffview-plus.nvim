# Phase 5: view, layout, and buffer ownership

Phase 5 moves editor-resource ownership out of the inherited scene classes and
into small composable objects. The existing `View`, `Layout`, and `Window`
classes remain as dispatch facades for concrete views and layouts, but no
longer define the ownership contract.

## Components

- `ViewShell` owns the view lifecycle and gates every registered action while
  a view is loading or closing. Its `EffectScope` releases resources in reverse
  registration order and closes child scopes before parent resources.
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

## Effect scopes

Every view exposes `view.effects`, which is the same scope owned by its
`ViewShell`. A resource may provide `release()`, `close()`, `cancel()`,
`kill()`, or `destroy()`, or supply an explicit disposer:

```lua
view.effects:own(timer)
view.effects:own(subscription, function(unsubscribe)
  unsubscribe()
end)

local request_scope = view.effects:child()
request_scope:listen(function(_, reason)
  -- Stop publishing completion results after cancellation.
end)
```

Closing a scope marks it cancelled before notifying listeners. Cleanup is
idempotent, continues after individual disposer failures, and returns those
errors to callers. A resource registered after cancellation is disposed
immediately. Long-running callbacks should call `scope:check()` before
committing state.

## Removed workaround

The shared null buffer no longer installs `<Nop>` mappings for `do`, `dp`, or
merge-side variants. Those mappings were domain policy attached to a sentinel
buffer and could overwrite user buffer-local state. Interactive commands now
enter through `ActionRegistry`, whose availability check delegates to the
current `ViewShell`.

The remaining scene and adapter dispatch facades still use the old OOP module;
extending that module is prohibited. Runtime primitives and new domain code use
plain annotated tables.
