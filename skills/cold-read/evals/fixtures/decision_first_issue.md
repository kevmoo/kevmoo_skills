# Empty config.yaml crashes startup with NoSuchMethodError instead of a clear error

`dart bin/main.dart` with an empty `config.yaml` exits with an unhandled
`NoSuchMethodError` from `Config.fromYaml` (`lib/src/config.dart:22`). Expected:
a `config.yaml is empty` error or the documented defaults. Dart 3.5.0, macOS 14.6.

## Steps to reproduce

1. Create an empty `config.yaml`.
2. Run `dart bin/main.dart`.

```text
Unhandled exception:
NoSuchMethodError: The method '[]' was called on null.
#0  Config.fromYaml (package:sample/src/config.dart:22:18)
```

## Proposed fix

Return defaults when `loadYaml` yields `null`, or throw a `FormatException`
naming the file.
