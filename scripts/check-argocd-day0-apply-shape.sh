#!/usr/bin/env bash
# Regression fence for #218 — the SHAPE of the Day-0 ArgoCD kubectl apply.
#
# The module used to apply the argo-cd chart's FULL default render with
# `kubectl apply --server-side --force-conflicts` after the health gate: twelve
# kinds, bundled Dex included, force-taking field-manager ownership of argocd-cm
# and argocd-rbac-cm from argocd-controller on every re-fire (triggers_replace
# includes kubernetes_version, so a routine Kubernetes bump was enough). Once a
# consumer's RBAC policy lives in argocd-rbac-cm, that is an outage primitive.
# Decision: knowledge/decisions/0025-argocd-crd-apply-scope.md.
#
# Why a static fence and not a tofu test: the provisioner `command =` string is
# not observable from a `tofu test` assertion — no plan attribute exposes it —
# and the tftest that binds the PAYLOAD (tests/argocd-crd-scope.tftest.hcl)
# needs the live Image Factory + chart repo, so it runs only under the advisory
# `task tofu:test`. This fence is offline and rides `task tofu:ci`, which the
# required `tofu-validate` job runs, so the property has a BLOCKING gate. Same
# rationale as check-kubeconfig-endpoint-regen.sh and
# check-node-projection-wiring.sh.
#
# Asserts, inside the relevant top-level blocks of main.tf:
#   A1  null_resource.argocd_crds applies with `kubectl apply --server-side`.
#   A2  that command carries NO `--force-conflicts`.
#   A3  terraform_data.argocd_crds_render carries a precondition whose condition
#       references the projection locals — so the CRD-set guard cannot be
#       deleted silently.
#   A4  that command names a DEDICATED --field-manager. adr-0025 makes this one
#       of the three properties that make dropping --force-conflicts safe: without
#       it kubectl records the generic manager `kubectl`, which is both an
#       operator's ad-hoc apply and the stale owner the old force-apply already
#       left on argocd-cm/argocd-rbac-cm. Deleting the flag is otherwise invisible.
#   A5  the projection still FILTERS on kind == CustomResourceDefinition. The
#       plan-time name precondition is a subset test, so deleting the filter
#       yields the full twelve-kind render and still satisfies it — the exact
#       defect this fence exists for, caught here statically.
#   A6  triggers_replace does NOT name kubernetes_version. Re-adding it is a
#       one-line regression that re-fires the apply on every routine Kubernetes
#       bump against CRDs ArgoCD owns by then, which is now an apply FAILURE
#       rather than a silent overwrite.
#
# Hermetic: pure static analysis, no providers/network.
# Usage: scripts/check-argocd-day0-apply-shape.sh [path/to/main.tf]
#
# Exit codes:
#   0  all assertions hold
#   1  usage / precondition (input file missing)
#   3  an assertion failed
set -euo pipefail

MAIN="${1:-tofu/modules/talos-cluster/main.tf}"

if [ ! -f "$MAIN" ]; then
  echo "::error::check-argocd-day0-apply-shape: ${MAIN} not found" >&2
  exit 1
fi

# Print one top-level block by its opening declaration. Same column-0 model the
# sibling fences use: a top-level block opens at column 0 and closes at the first
# subsequent line whose first character is `}`.
block_of() {
  awk -v decl="$1" '
    index($0, decl) == 1 { inb = 1 }
    inb                  { print }
    inb && /^}/          { inb = 0 }
  ' "$MAIN"
}

fail=0

apply_blk="$(block_of 'resource "null_resource" "argocd_crds"')"
if [ -z "$apply_blk" ]; then
  echo "::error::check-argocd-day0-apply-shape: resource null_resource.argocd_crds not found in ${MAIN} — the Day-0 apply moved or was renamed; re-point this fence (#218)." >&2
  exit 3
fi

# A1 — the apply is a server-side kubectl apply.
if ! printf '%s\n' "$apply_blk" | grep -qE 'command[[:space:]]*=.*kubectl apply --server-side'; then
  echo "::error::check-argocd-day0-apply-shape: A1 — null_resource.argocd_crds does not run 'kubectl apply --server-side'. The CRDs must land server-side (the ApplicationSet CRD exceeds the client-side last-applied annotation limit)." >&2
  fail=1
fi

# A2 — and it does NOT force-take ownership.
if printf '%s\n' "$apply_blk" | grep -E 'command[[:space:]]*=' | grep -q -- '--force-conflicts'; then
  echo "::error::check-argocd-day0-apply-shape: A2 — the Day-0 apply passes --force-conflicts. This is a seed-then-hand-off path: the steady-state component ships the same three CRDs and ArgoCD syncs them server-side, so ArgoCD co-owns them from its first sync. Forcing here strips its ownership entries and rolls a GitOps-managed CRD schema back to the seed pin. A conflict is a real signal — 'the steady state has moved past this pin' — not something to steamroll. See knowledge/decisions/0025-argocd-crd-apply-scope.md." >&2
  fail=1
fi

# A3 — the CRD-set guard exists on the freeze.
freeze_blk="$(block_of 'resource "terraform_data" "argocd_crds_render"')"
if [ -z "$freeze_blk" ]; then
  echo "::error::check-argocd-day0-apply-shape: A3 — resource terraform_data.argocd_crds_render not found in ${MAIN}." >&2
  fail=1
elif ! printf '%s\n' "$freeze_blk" | grep -qE '^[[:space:]]*precondition[[:space:]]*\{'; then
  echo "::error::check-argocd-day0-apply-shape: A3 — terraform_data.argocd_crds_render carries no precondition. Without it a projection that stops matching the chart's render shape freezes and kubectl-applies a truncated CRD set instead of failing the plan." >&2
  fail=1
else
  # Both halves, named individually. "At least one condition mentions
  # local.argocd_*" is too weak once the freeze carries two preconditions:
  # hollowing either one would still leave the other matching, and the guard
  # that was deleted is the one that mattered. Completeness and exclusivity are
  # different properties, so each gets its own assertion.
  if ! printf '%s\n' "$freeze_blk" | grep -qE '^[[:space:]]*condition[[:space:]]*=.*local\.argocd_crd_names'; then
    echo "::error::check-argocd-day0-apply-shape: A3 — terraform_data.argocd_crds_render has no precondition referencing local.argocd_crd_names, so nothing asserts the projection still carries all three ArgoCD CRDs BY NAME. Without it a projection that stops matching the chart's render shape freezes and kubectl-applies a truncated CRD set instead of failing the plan." >&2
    fail=1
  fi
  if ! printf '%s\n' "$freeze_blk" | grep -qE '^[[:space:]]*condition[[:space:]]*=.*local\.argocd_crd_kinds'; then
    echo "::error::check-argocd-day0-apply-shape: A3 — terraform_data.argocd_crds_render has no precondition referencing local.argocd_crd_kinds, so nothing asserts the payload is EXCLUSIVELY CustomResourceDefinitions at plan time. The by-name check is a containment test and passes on the full twelve-kind render." >&2
    fail=1
  fi
fi

# A4 — and it records its writes under a manager of its own.
if ! printf '%s\n' "$apply_blk" | grep -E 'command[[:space:]]*=' | grep -qE -- '--field-manager=[^ "]+'; then
  echo "::error::check-argocd-day0-apply-shape: A4 — the Day-0 apply names no --field-manager, so kubectl records the generic manager 'kubectl'. That is indistinguishable from an operator's ad-hoc apply AND from the stale owner the pre-#218 force-apply already left on argocd-cm/argocd-rbac-cm, which is exactly the distinction adr-0025 relies on when it drops --force-conflicts." >&2
  fail=1
elif printf '%s\n' "$apply_blk" | grep -E 'command[[:space:]]*=' | grep -qE -- '--field-manager=kubectl([^-a-zA-Z0-9]|$)'; then
  echo "::error::check-argocd-day0-apply-shape: A4 — the Day-0 apply passes --field-manager=kubectl, which is the generic default it is supposed to replace. Use a dedicated manager name." >&2
  fail=1
fi

# A5 — the projection is EXCLUSIVE, not merely complete.
# The freeze's name precondition is a subset test (`contains`), so a projection
# that stopped filtering would still carry all three CRD names and pass it. The
# filter itself is the property, so assert the filter.
if ! grep -qE 'yamldecode\(doc\)\.kind, ""\) == "CustomResourceDefinition"' "$MAIN"; then
  echo "::error::check-argocd-day0-apply-shape: A5 — the CRD projection no longer filters on kind == \"CustomResourceDefinition\". Without that filter the payload is the chart's full default render (twelve kinds, bundled Dex included) and the by-name precondition still passes, because it only tests containment. This is the #218 defect itself." >&2
  fail=1
fi

# A6 — kubernetes_version stays OUT of the re-apply trigger set.
if [ -n "$freeze_blk" ]; then
  # `intrig`, not `int` — the latter is an awk built-in and is a syntax error as
  # a variable name.
  trig="$(printf '%s\n' "$freeze_blk" | awk '/^[[:space:]]*triggers_replace[[:space:]]*=/ {intrig=1} intrig {print} intrig && /^[[:space:]]*\]/ {intrig=0}')"
  if [ -z "$trig" ]; then
    echo "::error::check-argocd-day0-apply-shape: A6 — terraform_data.argocd_crds_render has no triggers_replace list to inspect; an intended chart bump would never re-apply." >&2
    fail=1
  elif printf '%s\n' "$trig" | grep -vE '^[[:space:]]*#' | grep -q 'kubernetes_version'; then
    echo "::error::check-argocd-day0-apply-shape: A6 — triggers_replace names kubernetes_version. The CRD payload does not depend on it (Helm copies crds/ through verbatim), so this only makes a routine Kubernetes upgrade re-fire the apply against CRDs ArgoCD owns by then — which, without --force-conflicts, fails the whole tofu apply. See knowledge/decisions/0025-argocd-crd-apply-scope.md." >&2
    fail=1
  fi
fi

if [ "$fail" -eq 0 ]; then
  echo "check-argocd-day0-apply-shape: OK — Day-0 apply is server-side under a dedicated field manager, carries no --force-conflicts, applies an exclusively-CRD projection guarded at plan time, and does not re-fire on a Kubernetes bump."
  exit 0
fi
# 3, not 1: the header reserves 1 for "the fence could not run" (missing input).
# Collapsing the two would make a broken invocation indistinguishable from a
# violated invariant to any consumer that branches on the code.
exit 3
