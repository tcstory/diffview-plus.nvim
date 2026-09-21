# Phase 6: VCS adapter ports

Phase 6 replaces UI-side adapter identity checks with declared capabilities and
introduces a common result/error/cancellation contract for adapter queries.
Adapters own VCS-specific behavior; callers decide how errors are presented.

## Contracts

- `vcs/capability.lua` is the stable feature vocabulary. Action availability,
  merge opening, pin-local mode, and index watching query capabilities rather
  than checking Git/Hg/JJ/P4 classes.
- `vcs/query.lua` represents success, cancellation, unsupported operations,
  process failures, parse failures, and validation failures without displaying
  messages. Cancellation is cooperative and can be checked before and after a
  synchronous adapter boundary.
- `vcs/path_args.lua` builds argv arrays and keeps each path in one process
  argument. Git literal pathspecs and `revision:path` object names have named
  builders. JJ retains its fileset encoder because its positional arguments
  are expressions rather than ordinary paths.
- Git status/history/merge/stage responsibilities live in separate modules.
  Status parsing is process-free and covered by property-style cases including
  spaces, tabs, newlines, leading dashes, glob characters, and Unicode.

## Capability matrix

| Capability | Git | JJ | Hg | P4 |
|---|:---:|:---:|:---:|:---:|
| Status/history/revision/completion | yes | yes | yes | yes |
| Merge context | yes | yes | yes | yes |
| Restore | yes | yes | yes | yes |
| Stage/index watch | yes | no | no | no |
| Transactional merge view | yes | no | no | no |
| Pin local history | yes | no | yes | no |

## Integration matrix

CI uses Ubuntu 24.04 with Git 2.53.0, JJ 0.39.0, Mercurial 7.0.1, and
Perforce r24.2. The versions are explicit so changes to a VCS protocol or
output format are reviewed independently from application changes.

Hg and P4 integration tests skip automatically when their binaries are absent.
They may also be skipped explicitly while retaining unit coverage:

```sh
DIFFVIEW_SKIP_HG_INTEGRATION=1 make test
DIFFVIEW_SKIP_P4_INTEGRATION=1 make test
```

These variables affect integration availability only; capability and parser
contract tests always run.
