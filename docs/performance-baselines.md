# Performance baselines

The refactor keeps deterministic scale contracts in the functional suite. They
are deliberately based on state/projection work rather than network or disk
speed, so they remain useful on CI machines:

| Workload | Contract | Test |
|---|---:|---|
| DiffView refresh state | filter/prune 1,000 entries in under 100 ms | `refactor_scale_spec.lua` |
| FileHistory streaming | append 1,000 entries in under 100 ms without replacing the entry list | `refactor_scale_spec.lua` |
| Merge transaction | create and resolve 100 stable conflict identities in under 100 ms | `refactor_scale_spec.lua` |
| Panel redraw | change one row in a 1,000-line buffer in under 100 ms and write only that row | `renderer_patch_spec.lua` |

Run the baselines with:

```bash
TEST_PATH=lua/diffview/tests/functional/refactor_scale_spec.lua make test
TEST_PATH=lua/diffview/tests/functional/renderer_patch_spec.lua make test
```

The 100 ms limits are regression budgets, not claims about interactive latency
on every machine. End-to-end adapter integration remains covered separately by
the Git and JJ suites, where wall time depends on the installed VCS and file
system.
