# Prune dead git_extensions helpers and privatize file-local symbols

Prune unreferenced `GitDirExtensions` helpers, move test-only git config
mutation into `test/test_helpers.dart`, and restrict 42 file-local `lib/src/`
declarations to library-private scope to narrow the internal API surface.

- **Non-obvious exclusions**: 9 remaining public items appear in cross-library
  signatures across `lib/src/` and stay public intentionally.
- **Second-pass analyzer cleanup**: Removed 3 newly unreferenced private helpers
  after inlining `_ensureWorktreeTracked`.
