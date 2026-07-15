# negative-fixture

Deliberately malformed OpenSpec spec: no `## Purpose`, no `## Requirements`,
a requirement without a SHALL sentence and without any scenario. CI copies
this file into a temporary `openspec/specs/negative-fixture/` directory and
asserts `openspec validate --all --strict --no-interactive` exits non-zero —
proving the strict validator actually bites on directly-authored specs
(guards against a future openspec release going warn-only or change-gated;
see ADR-0015 §Validation).

### Requirement: Broken

This text carries no normative keyword and no scenario.
