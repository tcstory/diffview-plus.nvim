# Phase 7: DiffView and file panel

Phase 7 gives DiffView one state owner and makes its daily review workflow
discoverable without memorized mappings.

## State and commands

`scene/views/diff/store.lua` owns the file dictionary, reviewed keys,
hide-reviewed flag, path filter, and current entry. `DiffView.files` and the
legacy panel fields remain temporary projections for public integrations, but
production mutations go through the store.

`scene/views/diff/command.lua` is the mutation boundary for stage, unstage,
restore, refresh, filtering, listing style, flattened directories, and review
visibility. ActionRegistry command specs receive the active view explicitly.
The Git index watcher and `GitSignsChanged` listener dispatch refresh intents
tagged with their source instead of invoking refresh directly.

## File panel controls

The file panel winbar is projected from immutable `ui.component` values by
`ui.component_renderer` and routed through the single `UIRouter`. It exposes:

- Actions, review marking, hide/show reviewed files, and path filtering;
- list/tree mode and flattened-directory mode;
- stage/unstage, restore, and refresh;
- layout cycling and edit/split/tab opening.

Unavailable actions remain visible but disabled with a reason from the action
registry. The Actions control opens the complete context-sensitive palette,
including each named layout and opening mode. Clicking a file still selects it,
so the complete open/review/stage/restore flow is available with the mouse.
Previous/next file-diff controls live beside the `LOCAL` label in the diff
winbar, where they remain visible independently of the file-panel width.

## Filtering

The Filter control prompts for a case-insensitive literal path fragment. An
empty value clears it. Filtering and hide-reviewed compose in `DiffStore`, so
navigation, section counts, list rendering, and tree rendering share the same
visibility decision.

The Phase 7 contract tests cover store ownership, notifications, explicit
refresh sources, command routing, nested immutable components, route cleanup,
and the toolbar's daily-review action set.
