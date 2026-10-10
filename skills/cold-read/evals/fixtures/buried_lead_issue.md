# Investigation of config loading behavior in the sample CLI

While investigating the codebase to understand how configuration is loaded, I
traced the startup path through `bin/main.dart`, which calls `loadConfig()` in
`lib/src/config.dart`. That function reads `config.yaml` from the current
directory, parses it with `package:yaml`, and converts the result into a
`Config` object via `Config.fromYaml()`. The `Config` class holds the `name`,
`port`, and `verbose` fields and is passed to `Server.start()`.

Commit `a1b2c3d` and PR #41 introduced `Config.fromYaml()` to replace the
earlier JSON-based loader, and PR #58 later added the `verbose` flag.

After tracing all of this, I noticed that when `config.yaml` is empty, the
process exits with an unhandled `NoSuchMethodError` on `null` instead of a
clear error message or defaults.

## Steps to reproduce

1. Create an empty `config.yaml`.
2. Run `dart bin/main.dart`.

## Expected

A clear error such as `config.yaml is empty` or the documented defaults.

## Actual

```text
Unhandled exception:
NoSuchMethodError: The method '[]' was called on null.
#0  Config.fromYaml (package:sample/src/config.dart:22:18)
```

Observed on Dart 3.5.0, macOS 14.6.

## Possible approaches

There are several architectural options here. One could introduce a
`ConfigSource` abstraction with pluggable loaders, or adopt a schema validation
layer, or refactor `Config` into an immutable builder pattern that validates
every field on construction. Each has trade-offs around extensibility and
testing that may be worth discussing with the team.
