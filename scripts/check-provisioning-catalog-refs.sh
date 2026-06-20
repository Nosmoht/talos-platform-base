#!/usr/bin/env bash
# check-provisioning-catalog-refs.sh — cross-reference gate for the γ'
# node-capability-composition model (docs/adr-node-capability-composition.md).
#
# Asserts the load-bearing equivalence the composition guards rely on:
#   { atoms a base provisioning profile `provides` }  ==
#   { Layer-C atoms with discovery_source: talos-machine-config }
#
# composition.tf defines "provisioned atom" SELF-CONTAINED as "provided by some
# catalog profile" (it does NOT read the registry at plan time, by design). That
# is sound only while the catalog's `provides` set matches the registry's
# talos-machine-config set. This gate enforces that match so a registry-only atom
# addition (or a catalog-only one) cannot silently defeat the symmetry guard.
#
# Also validates every provided atom id is kebab-case (label-syntax safe — it is
# interpolated into a platform.io/hardware-feature.<atom> node label).
#
# Usage: scripts/check-provisioning-catalog-refs.sh
# Exit:  0 = sets match; 1 = mismatch / malformed; 2 = environment error.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILES="$REPO_ROOT/tofu/modules/talos-cluster/profiles.tf"
REGISTRY="$REPO_ROOT/docs/platform-hardware-features.yaml"

command -v yq >/dev/null 2>&1 || { echo "ERROR: yq (mikefarah v4+) required" >&2; exit 2; }
[ -f "$PROFILES" ] || { echo "ERROR: catalog not found: $PROFILES" >&2; exit 2; }
[ -f "$REGISTRY" ] || { echo "ERROR: registry not found: $REGISTRY" >&2; exit 2; }

# Registry: atom ids with discovery_source == talos-machine-config (= provisioned).
registry_atoms="$(yq -r '.hardware_features[] | select(.discovery_source == "talos-machine-config") | .id' "$REGISTRY" | sort -u)"

# Catalog: atoms appearing inside any profile `provides = [ ... ]` list. The grep
# extracts the bracket body, then the quoted kebab-case ids within it.
catalog_atoms="$(grep -oE 'provides[[:space:]]*=[[:space:]]*\[[^]]*\]' "$PROFILES" \
  | grep -oE '"[a-z0-9-]+"' | tr -d '"' | sort -u)"

# Kebab-case guard: any provided token that is NOT kebab-case would have been
# dropped by the extraction above, so a malformed token surfaces as a set
# mismatch. Additionally flag a literal non-kebab provides entry for a clear msg.
malformed="$(grep -oE 'provides[[:space:]]*=[[:space:]]*\[[^]]*\]' "$PROFILES" \
  | grep -oE '"[^"]*"' | tr -d '"' | grep -vE '^[a-z0-9-]+$' || true)"
if [ -n "$malformed" ]; then
  echo "FAIL: non-kebab-case provided atom id(s) in $PROFILES:" >&2
  echo "$malformed" | sed 's/^/  - /' >&2
  exit 1
fi

if [ "$registry_atoms" != "$catalog_atoms" ]; then
  echo 'FAIL: provisioning-catalog provides set != registry talos-machine-config set.' >&2
  echo "--- registry (discovery_source: talos-machine-config) ---" >&2
  echo "$registry_atoms" | sed 's/^/  /' >&2
  echo "--- catalog (profile provides) ---" >&2
  echo "$catalog_atoms" | sed 's/^/  /' >&2
  echo "Reconcile docs/platform-hardware-features.yaml and tofu/modules/talos-cluster/profiles.tf." >&2
  exit 1
fi

count="$(printf '%s\n' "$catalog_atoms" | grep -c . || true)"
echo "OK: provisioning-catalog provides == registry talos-machine-config atoms (${count}): $(echo "$catalog_atoms" | tr '\n' ' ')"
