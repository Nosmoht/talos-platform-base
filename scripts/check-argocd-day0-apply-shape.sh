#!/usr/bin/env bash
# Usage: scripts/check-argocd-day0-apply-shape.sh [path/to/argocd-crds.tf]
set -euo pipefail

MAIN="${1:-tofu/modules/talos-cluster/argocd-crds.tf}"

if [ ! -f "$MAIN" ]; then
  echo "::error::check-argocd-day0-apply-shape: ${MAIN} not found" >&2
  exit 1
fi

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

if ! printf '%s\n' "$apply_blk" | grep -qE 'command[[:space:]]*=.*kubectl apply --server-side'; then
  echo "::error::check-argocd-day0-apply-shape: A1 — null_resource.argocd_crds does not run 'kubectl apply --server-side'. The CRDs must land server-side (the ApplicationSet CRD exceeds the client-side last-applied annotation limit)." >&2
  fail=1
fi

if printf '%s\n' "$apply_blk" | grep -E 'command[[:space:]]*=' | grep -q -- '--force-conflicts'; then
  echo "::error::check-argocd-day0-apply-shape: A2 — the Day-0 apply passes --force-conflicts. This is a seed-then-hand-off path: the steady-state component ships the same three CRDs and ArgoCD syncs them server-side, so ArgoCD co-owns them from its first sync. Forcing here strips its ownership entries and rolls a GitOps-managed CRD schema back to the seed pin. A conflict is a real signal — 'the steady state has moved past this pin' — not something to steamroll. See knowledge/decisions/0025-argocd-crd-apply-scope.md." >&2
  fail=1
fi

freeze_blk="$(block_of 'resource "terraform_data" "argocd_crds_render"')"
if [ -z "$freeze_blk" ]; then
  echo "::error::check-argocd-day0-apply-shape: A3 — resource terraform_data.argocd_crds_render not found in ${MAIN}." >&2
  fail=1
elif ! printf '%s\n' "$freeze_blk" | grep -qE '^[[:space:]]*precondition[[:space:]]*\{'; then
  echo "::error::check-argocd-day0-apply-shape: A3 — terraform_data.argocd_crds_render carries no precondition. Without it a projection that stops matching the chart's render shape freezes and kubectl-applies a truncated CRD set instead of failing the plan." >&2
  fail=1
else
  # Check completeness and exclusivity independently.
  if ! printf '%s\n' "$freeze_blk" | grep -qE '^[[:space:]]*condition[[:space:]]*=.*local\.argocd_crd_names'; then
    echo "::error::check-argocd-day0-apply-shape: A3 — terraform_data.argocd_crds_render has no precondition referencing local.argocd_crd_names, so nothing asserts the projection still carries all three ArgoCD CRDs BY NAME. Without it a projection that stops matching the chart's render shape freezes and kubectl-applies a truncated CRD set instead of failing the plan." >&2
    fail=1
  fi
  if ! printf '%s\n' "$freeze_blk" | grep -qE '^[[:space:]]*condition[[:space:]]*=.*local\.argocd_crd_kinds'; then
    echo "::error::check-argocd-day0-apply-shape: A3 — terraform_data.argocd_crds_render has no precondition referencing local.argocd_crd_kinds, so nothing asserts the payload is EXCLUSIVELY CustomResourceDefinitions at plan time. The by-name check is a containment test and passes on the full twelve-kind render." >&2
    fail=1
  fi
fi

if ! printf '%s\n' "$apply_blk" | grep -E 'command[[:space:]]*=' | grep -qE -- '--field-manager=[^ "]+'; then
  echo "::error::check-argocd-day0-apply-shape: A4 — the Day-0 apply names no --field-manager, so kubectl records the generic manager 'kubectl'. That is indistinguishable from an operator's ad-hoc apply AND from the stale owner the pre-#218 force-apply already left on argocd-cm/argocd-rbac-cm, which is exactly the distinction adr-0025 relies on when it drops --force-conflicts." >&2
  fail=1
elif printf '%s\n' "$apply_blk" | grep -E 'command[[:space:]]*=' | grep -qE -- '--field-manager=kubectl([^-a-zA-Z0-9]|$)'; then
  echo "::error::check-argocd-day0-apply-shape: A4 — the Day-0 apply passes --field-manager=kubectl, which is the generic default it is supposed to replace. Use a dedicated manager name." >&2
  fail=1
fi

# Names alone cannot prove that non-CRD documents are excluded.
if ! grep -qE 'yamldecode\(doc\)\.kind, ""\) == "CustomResourceDefinition"' "$MAIN"; then
  echo "::error::check-argocd-day0-apply-shape: A5 — the CRD projection no longer filters on kind == \"CustomResourceDefinition\". Without that filter the payload is the chart's full default render (twelve kinds, bundled Dex included) and the by-name precondition still passes, because it only tests containment. This is the #218 defect itself." >&2
  fail=1
fi

if [ -n "$freeze_blk" ]; then
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
exit 3
