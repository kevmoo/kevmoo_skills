# Emit a 1-line hint in src/formatters/SnapshotFormatter.ts when a canvas is present

Add a `chunks.push('Note: canvas element pruned...')` check at line 391 of
[`src/formatters/SnapshotFormatter.ts`](https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/src/formatters/SnapshotFormatter.ts#L378-L394)
(called from
[`src/TextSnapshot.ts#L59-L63`](https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/src/TextSnapshot.ts#L59-L63))
whenever `this.#snapshot.verbose` is `false` and `root.children.length === 0`,
and add a section to `skills/a11y-debugging/SKILL.md`.
