## Why

Nothing in CI ever rendered `kubernetes/bootstrap/cilium/values.yaml`. Helm does
not run `--strict`, so a value spelling the pinned chart has REMOVED is dropped
silently — the file keeps claiming a configuration the cluster does not have, with
no error at render or apply time.

That is not hypothetical: `encryption.strictMode.{enabled,cidr,
allowRemoteNodeIdentities}` sat in this file after Cilium 1.20 removed the flat
form, so strict-mode encryption was simply not configured for any consumer who
copied it. The defect was fixed by hand at the bump, and the requirement added
there was reviewer-enforced only — which the spec said outright.

`.ci-renderable-components.txt` names only `argocd`, `tofu-validate.yml` is
path-filtered to `tofu/**`, and the one chart-pulling job is advisory by design. So
no existing gate covered the file.

## What Changes

- `scripts/check-cilium-reference-values.py` validates every value path in the file
  against the pinned chart's own `values.schema.json`, and fails naming each path
  the chart does not declare.
- Wired into BOTH `task gitops:validate` and the `gitops-validate.yml` validate job
  — same script, same verdict, so a local pass means what a CI pass means.
- The chart version comes from `variables.tf`, which #210 made the single source of
  truth, so the check cannot drift from what the module renders.

Two deliberate design choices, both stated in the spec rather than left implicit:

1. **Registry outage SKIPS loudly and exits 0.** The repo already decided a
   chart-registry outage must not block unrelated merges. The stated hole: during an
   outage a removed spelling can merge.
2. **`yq`, not PyYAML.** The CI job already installs a pinned `yq`; PyYAML is a
   declared dependency nowhere in this repo. Depending on it would make the gate
   skip silently on a runner without it, and a gate that can vacuously pass is worse
   than no gate. A missing `yq` therefore exits non-zero, loud.

The check covers the removed-spelling failure mode only. A changed DEFAULT under a
spelling that still parses stays reviewer-enforced, because no values schema can
express it — that half is bound for the seed by the key-set and value pins in
`cilium-cni-delivery`'s seed-surface requirement.

## Capabilities

- `cilium-cni-delivery` — MODIFIED: the Day-2 reference-values requirement's
  removed-spelling half becomes mechanically enforced, with the outage-skip hole and
  the reviewer-enforced changed-default half both named, plus a scenario for the
  removed-spelling case.

## Impact

No runtime change. `task gitops:validate` gains a networked step; a PR that
reintroduces a removed value spelling now fails a required check instead of shipping
a silently misconfigured reference file.
