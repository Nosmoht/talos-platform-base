#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILES="$REPO_ROOT/tofu/modules/talos-cluster/profiles.tf"
REGISTRY="$REPO_ROOT/platform-hardware-features.yaml"

command -v yq >/dev/null 2>&1 || { echo "ERROR: yq (mikefarah v4+) required" >&2; exit 2; }
[ -f "$PROFILES" ] || { echo "ERROR: catalog not found: $PROFILES" >&2; exit 2; }
[ -f "$REGISTRY" ] || { echo "ERROR: registry not found: $REGISTRY" >&2; exit 2; }

registry_atoms="$(yq -r '.hardware_features[] | select(.discovery_source == "talos-machine-config") | .id' "$REGISTRY" | sort -u)"

profiles_flat="$(tr '\n' ' ' < "$PROFILES")"

catalog_atoms="$(printf '%s' "$profiles_flat" | grep -oE 'provides[[:space:]]*=[[:space:]]*\[[^]]*\]' \
  | grep -oE '"[a-z0-9-]+"' | tr -d '"' | sort -u)"

malformed="$(printf '%s' "$profiles_flat" | grep -oE 'provides[[:space:]]*=[[:space:]]*\[[^]]*\]' \
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
  echo "Reconcile platform-hardware-features.yaml and tofu/modules/talos-cluster/profiles.tf." >&2
  exit 1
fi

count="$(printf '%s\n' "$catalog_atoms" | grep -c . || true)"
echo "OK: provisioning-catalog provides == registry talos-machine-config atoms (${count}): $(echo "$catalog_atoms" | tr '\n' ' ')"
