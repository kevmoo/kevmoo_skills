---
name: encapsulated-method-object
description: |-
  Apply the "Encapsulated Method Object" refactoring pattern to simplify functions with deeply nested scopes, bloated closures, and heavy shared local state.
license: Apache-2.0
key_features:
  - Method Object extraction
  - class-based encapsulation
  - Closure refactoring
---

## 1. When to use this skill

Use this skill when you encounter a Dart function or class method suffering
from the "Bloated Closure" or "Deeply Nested Scope" smell. Specifically, target
functions matching these criteria:

*   **Deeply Nested Scope**: The function declares one or more inner/local
    functions to perform sub-tasks.
*   **Shared Local State**: Those local functions rely heavily on capturing
    variables declared in the outer function's scope (closure capturing).
*   **High Complexity**: The top-level function contains many local variables,
    is difficult to unit test in isolation, or has high cyclomatic complexity.
*   **Parameter Bloat**: If you try to extract local functions to separate
    methods, you must pass large amounts of state as parameters.

### Core Concepts

This is a Dart-specific variation of Martin Fowler's classic refactoring
**"Replace Method with Method Object"**. It consists of three primary elements:

1.  **The Smell**: A single monolithic function containing multiple local
    variables and nested functions that form a dense web of shared state.
2.  **Phase 1: "Method Object" Extraction**: The function's logic is
    migrated into a dedicated class. The parameters of the original function
    become constructor arguments, local variables are promoted to instance
    fields, and inner functions become instance methods. State-sharing is
    simplified because all methods can access instance fields directly.
3.  **Phase 2: Facade Delegation**: To preserve the public API and prevent
    the namespace of the library/file from being polluted by a class only
    meant to serve a single function, the runner class is made **private**
    (prefixed with an underscore `_`). The original public function remains
    as a simple facade, which instantiates the private class and calls its
    main orchestrator method (typically `run()`).

## 2. How to use this skill (The Workflow)

When executing this pattern, follow these procedural steps:

1.  **Discovery & Identification**:
    *   Scan the target library for candidates using the heuristics described
        below (regex patterns, local scope variable counts, nested methods).
    *   Confirm that the code has sufficient test coverage so that you can
        verify behavior before and after the refactoring.

2.  **Analyze Dependencies & Scopes**:
    *   Identify all input parameters of the outer function. These will become
        the constructor arguments of the private class.
    *   Identify all mutable or final local variables in the outer function's
        body. These will be promoted to instance fields of the private class.
    *   Identify if the outer function is a method of another class. If so,
        you will need to pass the outer class's instance (`this`) to the
        private class's constructor to enable outer dependency and method
        integration.

3.  **Draft the Private Runner Class**:
    *   Create a private class named `_OriginalFunctionNameRunner` (or
        `_OriginalFunctionNameState` if more appropriate).
    *   Declare all target fields as private (e.g., final parameters, private
        state fields).
    *   Create a constructor that accepts the required inputs.
    *   Implement an entry point method, typically `run()`.

4.  **Extract Logical Sub-tasks**:
    *   Port the body of each inner/local function into a private instance
        method on the runner class.
    *   Clean up variable references: replace direct closure capturing with
        access to the class's private instance fields.
    *   Remove unnecessary parameters that were previously used to pass state
        between nested scopes.

5.  **Construct the Facade**:
    *   Replace the body of the original public function with a single call
        to the private runner class.
    *   Prefer fat-arrow syntax (`=>`) for the facade if it fits on a single
        line.

6.  **Verify Integrity**:
    *   Run `dart format` to ensure optimal code presentation.
    *   Run `dart analyze` to ensure there are no static errors or warnings.
    *   Run unit and integration tests to guarantee that no behavioral
        regressions were introduced.

## 3. Common Patterns

Here are the concrete Dart transformations representing this pattern.

### Pattern A: Basic Bloated Closure

**Before: The Bloated Closure Smell**
```dart
Result processOrder(Order order, User user, PaymentDetails payment) {
  bool isValidated = false;
  List<String> auditLogs = [];

  void validate() {
    if (order.items.isEmpty) throw Exception("Empty order");
    isValidated = true;
    auditLogs.add("Validated by ${user.id}");
  }

  void charge() {
    if (!isValidated) throw Exception("Must validate first");
    // complex charging logic using payment details...
    auditLogs.add("Charged ${payment.method}");
  }

  validate();
  charge();
  
  return Result(success: true, logs: auditLogs);
}
```

**After: Encapsulated Method Object (Facade + Private Runner)**
```dart
// The Facade (Original API signature preserved)
Result processOrder(Order order, User user, PaymentDetails payment) =>
    _ProcessOrderRunner(order, user, payment).run();

// The Method Object (Private to the file/library)
class _ProcessOrderRunner {
  final Order _order;
  final User _user;
  final PaymentDetails _payment;
  
  // Local variables promoted to private instance fields
  bool _isValidated = false;
  final List<String> _auditLogs = [];

  _ProcessOrderRunner(this._order, this._user, this._payment);

  // Core Orchestrator
  Result run() {
    _validate();
    _charge();
    return Result(success: true, logs: _auditLogs);
  }

  // Nested scopes promoted to private instance methods
  void _validate() {
    if (_order.items.isEmpty) throw Exception("Empty order");
    _isValidated = true;
    _auditLogs.add("Validated by ${_user.id}");
  }

  void _charge() {
    if (!_isValidated) throw Exception("Must validate first");
    // complex charging logic using payment details...
    _auditLogs.add("Charged ${_payment.method}");
  }
}
```

### Pattern B: Complex Method Object (Async, Generics, and Class Context)

**Before: Monolithic Class Instance Method**
```dart
class DataProcessor {
  final StorageService storage;
  final Logger logger;

  DataProcessor(this.storage, this.logger);

  Future<List<T>> processDataBatch<T>(
    String batchId,
    List<Map<String, dynamic>> items,
    T Function(Map<String, dynamic>) parser,
  ) async {
    int successCount = 0;
    int errorCount = 0;
    final List<T> results = [];

    Future<void> processItem(Map<String, dynamic> item) async {
      try {
        final parsed = parser(item);
        results.add(parsed);
        successCount++;
        logger.log("Successfully parsed item in batch $batchId");
      } catch (e, stack) {
        errorCount++;
        logger.error("Failed to parse item", e, stack);
      }
    }

    Future<void> saveBatch() async {
      if (results.isNotEmpty) {
        await storage.saveBatch(batchId, results);
        logger.log("Saved batch $batchId. Success: $successCount, Errors: $errorCount");
      }
    }

    for (final item in items) {
      await processItem(item);
    }
    await saveBatch();

    return results;
  }
}
```

**After: Encapsulated Method Object with Outer Instance Binding**
```dart
class DataProcessor {
  final StorageService storage;
  final Logger logger;

  DataProcessor(this.storage, this.logger);

  // Facade remains identical. Generics map directly to the runner class.
  Future<List<T>> processDataBatch<T>(
    String batchId,
    List<Map<String, dynamic>> items,
    T Function(Map<String, dynamic>) parser,
  ) =>
      _ProcessDataBatchRunner<T>(this, batchId, items, parser).run();
}

class _ProcessDataBatchRunner<T> {
  // 1. Context Reference: Keep a reference to the enclosing class instance
  final DataProcessor _outer;

  // 2. Facade Inputs: Mapped to final instance fields
  final String _batchId;
  final List<Map<String, dynamic>> _items;
  final T Function(Map<String, dynamic>) _parser;

  // 3. Mutable State: Converted to class fields
  int _successCount = 0;
  int _errorCount = 0;
  final List<T> _results = [];

  _ProcessDataBatchRunner(
    this._outer,
    this._batchId,
    this._items,
    this._parser,
  );

  // 4. Asynchronous Core Entry Point
  Future<List<T>> run() async {
    for (final item in _items) {
      await _processItem(item);
    }
    await _saveBatch();
    return _results;
  }

  // 5. Ported Helper Instance Methods
  Future<void> _processItem(Map<String, dynamic> item) async {
    try {
      final parsed = _parser(item);
      _results.add(parsed);
      _successCount++;
      // Access enclosing class dependencies via the context reference
      _outer.logger.log("Successfully parsed item in batch $_batchId");
    } catch (e, stack) {
      _errorCount++;
      _outer.logger.error("Failed to parse item", e, stack);
    }
  }

  Future<void> _saveBatch() async {
    if (_results.isNotEmpty) {
      await _outer.storage.saveBatch(_batchId, _results);
      _outer.logger.log(
        "Saved batch $_batchId. "
        "Success: $_successCount, Errors: $_errorCount",
      );
    }
  }
}
```

## 4. Constraints

To verify safe, high-fidelity operations, always obey the following guardrails:

*   **API Footprint Preservation**: The original public function signature
    (parameters, return type, annotations, and generics) MUST be strictly
    preserved without any breaking changes.
*   **Strict Class Encapsulation**: The runner class MUST be prefixed with
    an underscore (`_`) to ensure it remains private to the enclosing Dart
    library file, preventing external namespace pollution.
*   **Single-use Execution Scope**: The private runner class represents
    the state of a single invocation. Instance properties are transient state.
    Do NOT store the runner instance long-term or call `run()` more than
    once on the same instance.
*   **Constructor Purity**: Constructors should only map inputs and perform
    lightweight, non-throwing field initialization. Complex logic,
    asynchronous operations, or side effects MUST live in `run()`.
*   **Verification Checkpoints**: All refactored code must be formatted using
    `dart format`, pass static checks (`dart analyze`) with zero diagnostics,
    and execute all tests successfully (`dart test`).

## 5. Strategies for Discovery

Use the following techniques and tools to discover bloated closures:

### Ripgrep Detection Regexes

Run the following safe, read-only search operations to isolate candidate code:

```bash
# Finds inner function declarations (void, future, or custom type) indented inside block scope
grep -rnE '^\s{4,}(void|Future<|[A-Z]\w*(<.*>)?)\s+[a-z]\w*\s*\(.*\)\s*(async)?\s*\{' lib/
```

### Context Cues (Static Inspection)

Inspect code surfaces exhibiting:
1.  Nested loops alongside locally defined function scopes.
2.  Methods capturing numerous variables declared in their parent closure block.
3.  Extensive local variable setups preceding multiple internal callback mappings.
