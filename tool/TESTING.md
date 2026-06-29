# Testing in this Repository

This repository follows automated testing and linting standards for skills to ensure every skill is robust and self-contained.

## Implemented Layers

### Layer 1: SKILL.md (Contract)
Every skill in this repository has a `SKILL.md` file defining its contract, triggers, and rules.

### Layer 3: Unit Tests
We have automated tests to validate skill standards and run unit tests for any deterministic scripts associated with skills.

### Layer 8: Skill Linting & Validation
We use `dart_skills_lint` to verify path hygiene (relative vs. absolute paths) and formatting compliance.

## How to Run Tests

Navigate to the `tool/` directory and run standard Dart tests:

```bash
cd tool
dart pub get
dart test
```
