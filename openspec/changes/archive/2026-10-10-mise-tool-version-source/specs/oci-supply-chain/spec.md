## MODIFIED Requirements

### Requirement: The signing tool's version is pinned and the pin reaches the runner

The version of every tool the publish workflow installs to produce or push a
release artifact SHALL be declared in that workflow AND passed explicitly to
the action that installs it. A tool an action bundles is pinned by the
action's commit SHA instead. An installer action invoked without a version input resolves its
own default, so the declared pin is decorative and the tool that actually signs
is whatever that action happens to ship — a floating tool version on the
supply-chain path, invisible to any drift check.

#### Scenario: The declared cosign version is the one that signs

- **WHEN** the publish workflow installs cosign
- **THEN** the installer is given the version declared in the publish
  workflow, rather than falling back to the installer action's own default
