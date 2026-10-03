# Design

`talos_version` selects legacy versus native patches;
`talos_install_version` remains independent.
Use the existing two-pass composition order. Map module-owned settings to
native documents and keep caller patches verbatim. Generate per-role proxy
and scheduling settings only on control planes. Preserve Factory installer
selection and per-node override precedence. No new public inputs or outputs.

Keep 1.13 tests and add 1.14 examples and tests. Validate real provider output
with Talos 1.14.2, not just successful provider parsing. Document that this
proves configuration acceptance, not live hardware or storage behavior.
