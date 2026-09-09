## 1. Module interface

- [x] 1.1 Mark `cilium_values_override` sensitive; add the map-shape and
      joint-key validations.
- [x] 1.2 Add typed `cilium_k8s_service_host` / `cilium_k8s_service_port` with
      raw-render format guards; wire them into the computed layer in place of
      the hardcoded KubePrism literals.
- [x] 1.3 Add `cilium_self_management_values_source` with its three validation
      blocks; replace the override-drop reject on `cilium_self_management`.

## 2. Emitted Application

- [x] 2.1 Hoist the joint keys; bifurcate `cilium_self_management_spec` into the
      single-source and multi-source arms.
- [x] 2.2 Emit the module-set layer as `cilium_self_management_values` with a
      generated header carrying the values-digest, and annotate the
      Application with the same digest.
- [x] 2.3 Add the `check` blocks for AppProject scope and for an override
      emptied while the values source is still wired.
- [x] 2.4 Mirror the new outputs in the offline test fixture.
- [x] 2.5 `nonsensitive()` the seed observability markers, which the sensitive
      override otherwise taints.

## 3. Tests

- [x] 3.1 Replace guard leg C with the values-source requirement leg.
- [x] 3.2 Multi-source shape legs incl. the valueFiles ORDER assertion
      (red-green verified: reversing the order turns the leg red).
- [x] 3.3 Joint-key, map-shape, path and override-path rejection legs, each
      isolated to one validation block, plus negative-space controls.
- [x] 3.4 Typed endpoint legs incl. the toggle-off absence case.

## 4. Contracts and docs

- [x] 4.1 `schemas/cluster.schema.json`: three new closed keys + the two stale
      descriptions.
- [x] 4.2 Consumer shim: map the new keys, defaulting repo/revision from the
      SoT's own bootstrap identity.
- [x] 4.3 `cluster.yaml.example`, module `README.md`.
- [x] 4.4 `UPGRADING.md`: forward migration, rollback in both directions,
      break-glass, the two-artifact pairing, AppProject `sourceRepos`.
- [x] 4.5 `CHANGELOG.md` + the MAJOR marker on the commit and PR title.
- [x] 4.6 Knowledge bundle: ADR-0028 addendum, the surface map, `log.md`.
- [x] 4.7 Close #227 against this change — the commit and PR carry
      `Closes: #227`, so the merge closes it; #265 ships the typed inputs the
      issue asked for rather than reframing the request.

## 5. Review fixes (post-review, same change)

- [x] 5.1 `repo_url` git-remote-form allowlist (no `file://`, no embedded
      credentials) and a `values_path`/`override_path` distinctness guard.
- [x] 5.2 Warn when a values source is configured on the permissive `default`
      AppProject — the boundary the multi-source arm adds must not be the
      silent half.
- [x] 5.3 Split the port guard into format + range blocks so each is bindable,
      and correct the endpoint host shape to accept a bracketed IPv6 literal.
- [x] 5.4 Correct the measured render sink for the endpoint inputs
      (`KUBERNETES_SERVICE_HOST`/`_PORT` env vars, quoted — not a
      `cilium-config` key) and bind it with a render-layer leg.
- [x] 5.5 Bind the values-digest to its SUBJECT, assert `valuesObject`'s key
      SET rather than memberships, and pin the single-source arm against a
      golden captured from the pre-change revision.
- [x] 5.6 Make the multi-source output precondition falsifiable (the
      `$values/<path>` addressing predicate, not a list length).
- [x] 5.7 Retract the SOPS claim everywhere it appeared; state that Argo CD
      decrypts no Helm `valueFiles` source and key material at `override_path`
      is plaintext in git.
- [x] 5.8 Recurse `check-shim-key-parity.sh` one nesting level, and bind the
      four new schema rules red-green in the negative lint fixture.
