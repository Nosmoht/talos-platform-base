#!/usr/bin/env bash
# Regression fence for #123 (talos-cluster render -> machineConfig decoupling).
#
# data.helm_template renders are re-evaluated every plan and are NOT byte-stable
# (Sprig genCA at template time; helm-provider ordering). Consumed directly, every
# plan / Crossplane reconcile re-pushed a fresh machineConfig (#121). The fix
# freezes each render in state via a terraform_data carrying
# lifecycle { ignore_changes = [input] }; the ArgoCD-CRD render (a Day-2 kubectl
# convergence) additionally carries triggers_replace so an INTENDED chart/version
# bump still re-applies.
#
# This guard fails if that decoupling regresses. It does NOT use a hardcoded render
# allow-list: it derives every `data "helm_template" "<r>"` from the file and, for
# each, asserts:
#   1. the live render is referenced exactly once — as the `input =` capture of its
#      terraform_data.<r>_render freeze (a contents=/content=/sha256() consumer
#      re-introduces the #121 drift);
#   2. that freeze resource exists AND its OWN block carries ignore_changes=[input]
#      (per-resource, so a broken freeze cannot be masked by a decoy elsewhere);
#   3. CRD renders (name matches *crds*, a Day-2 kubectl re-apply path) additionally
#      carry triggers_replace, so deleting it (silent-non-apply on an intended bump)
#      is caught.
#
# Hermetic: pure static analysis of main.tf, no providers/network. Wired into
# `task tofu:ci`. Usage: scripts/check-render-determinism.sh [path/to/main.tf]
#
# NOTE (acknowledged limit): check (3) asserts triggers_replace is PRESENT, not that
# it ENUMERATES every render-affecting input of the data source. A render input added
# to the data source but not to triggers_replace is a silent-non-apply the static
# guard cannot see — the code comment on the freeze is the binding, keep it honest.
set -euo pipefail

MAIN="${1:-tofu/modules/talos-cluster/main.tf}"

if [ ! -f "$MAIN" ]; then
  echo "::error::check-render-determinism: ${MAIN} not found" >&2
  exit 1
fi

# Print the top-level resource block for terraform_data."<name>" (resource opens at
# column 0 and its closing brace is the first subsequent line starting with `}`).
block_of() {
  awk -v name="$1" '
    index($0, "resource \"terraform_data\" \"" name "\"") == 1 { inb = 1 }
    inb { print }
    inb && /^}/ { inb = 0 }
  ' "$MAIN"
}

fail=0

# Derive every helm render present in the module — not a hardcoded list, so a future
# render path cannot slip past the fence by simply not being named here.
renders=$(grep -oE 'data "helm_template" "[a-z_]+"' "$MAIN" | sed -E 's/.*"([a-z_]+)"$/\1/' | sort -u)
if [ -z "$renders" ]; then
  echo "::error::check-render-determinism: no data \"helm_template\" found in ${MAIN} — fence assumptions broken (did the module move?)." >&2
  exit 1
fi

count=0
for r in $renders; do
  count=$((count + 1))

  # (1) live render referenced exactly once, as the input= capture of its freeze.
  total=$(grep -cE "data\.helm_template\.${r}\[0\]\.manifest" "$MAIN" || true)
  capture=$(grep -cE "^[[:space:]]*input[[:space:]]+= data\.helm_template\.${r}\[0\]\.manifest" "$MAIN" || true)
  if [ "$total" -ne 1 ] || [ "$capture" -ne 1 ]; then
    echo "::error::check-render-determinism: data.helm_template.${r} must be referenced exactly once, as the input= capture of terraform_data.${r}_render (found total=${total}, capture=${capture}). A direct consumer (contents=/content=/sha256()) or an unmatched reference shape re-introduces the #123 machineConfig re-push — route it through terraform_data.${r}_render[0].output." >&2
    fail=1
  fi

  # (2) freeze exists AND its OWN block carries ignore_changes=[input].
  blk=$(block_of "${r}_render")
  if [ -z "$blk" ]; then
    echo "::error::check-render-determinism: freeze resource terraform_data.${r}_render is missing in ${MAIN} (#123)." >&2
    fail=1
    continue
  fi
  if ! printf '%s\n' "$blk" | grep -qE '^[[:space:]]*ignore_changes[[:space:]]*=[[:space:]]*\[input\]'; then
    echo "::error::check-render-determinism: terraform_data.${r}_render block lacks lifecycle { ignore_changes = [input] } — the freeze is broken and the render would re-capture every plan (#123)." >&2
    fail=1
  fi

  # (3) CRD renders feed a Day-2 kubectl re-apply and MUST re-capture on an intended
  #     bump — deleting triggers_replace turns the convergence path into a frozen
  #     seed (silent-non-apply). Seed renders intentionally have no triggers_replace.
  case "$r" in
    *crds*)
      if ! printf '%s\n' "$blk" | grep -qE '^[[:space:]]*triggers_replace[[:space:]]*='; then
        echo "::error::check-render-determinism: terraform_data.${r}_render (a Day-2 CRD kubectl-apply path) must carry triggers_replace so an intended chart/version bump re-applies; without it an intended bump silently never re-applies (#123)." >&2
        fail=1
      fi
      ;;
  esac
done

if [ "$fail" -eq 0 ]; then
  echo "check-render-determinism: OK — ${count} helm render(s) consumed only via frozen terraform_data (ignore_changes); CRD render(s) carry triggers_replace."
fi
exit "$fail"
