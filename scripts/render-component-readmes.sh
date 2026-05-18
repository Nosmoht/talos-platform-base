#!/usr/bin/env bash
# render-component-readmes.sh — generate per-component README.md files
# under kubernetes/base/infrastructure/<comp>/.
#
# Per docs/issue-workflow.md issue #35: each component dir must contain
# a README with sections (Purpose, Upstream chart, PNI capabilities,
# Helm-value overrides, Upgrade gotchas).
#
# Auto-extracted fields:
#   - chart repo/name/version  (from chart.lock.yaml when present)
#   - namespace name + PNI capability labels (from namespace.yaml)
#   - Helm top-level value keys (from values.yaml when present)
#
# Hand-curated fields live in the PURPOSE and GOTCHAS associative
# arrays below. Updating these is a deliberate doc act; the script is
# the deterministic glue, not the source of judgement.
#
# Usage:
#   scripts/render-component-readmes.sh           # write all 22 READMEs
#   scripts/render-component-readmes.sh --check   # exit 1 on drift
#   scripts/render-component-readmes.sh <comp>    # write only <comp>'s README

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFRA_DIR="$REPO_ROOT/kubernetes/base/infrastructure"
COMP_LIST="$REPO_ROOT/.ci-renderable-components.txt"

command -v yq >/dev/null 2>&1 || { echo "ERROR: yq not found in PATH" >&2; exit 2; }
[ -f "$COMP_LIST" ] || { echo "ERROR: $COMP_LIST not found" >&2; exit 2; }

# Hand-curated per-component metadata. bash 3.2 lacks `declare -A`, so
# both fields are exposed as case-statement functions instead.

purpose_of() {
  case "$1" in
    alloy) echo "Grafana Alloy agent — collects logs and metrics from cluster workloads and forwards them to the Loki/Prometheus stack via Prometheus remote-write and Loki push." ;;
    argocd) echo "ArgoCD GitOps engine — reconciles every other component in this base from git source via Multi-Source Applications." ;;
    cert-approver) echo "kubelet CSR approver — auto-approves serving certificates for kubelet so cert-manager can rotate them without manual intervention." ;;
    cert-manager) echo "cert-manager — issues, renews, and revokes X.509 certificates from ClusterIssuers (Vault, ACME, self-signed) for all in-cluster TLS." ;;
    dex) echo "Dex OIDC provider — federates upstream identity (GitHub, OIDC, LDAP) into a single in-cluster OIDC issuer consumed by ArgoCD, Grafana, and kubeconfig OIDC login." ;;
    external-secrets) echo "External Secrets Operator — synchronises Kubernetes Secrets from Vault, AWS SM, and other backends declared in ExternalSecret CRs." ;;
    kube-prometheus-stack) echo "kube-prometheus-stack — Prometheus, Alertmanager, kube-state-metrics, node-exporter, and Grafana, the platform's reference metrics + dashboards stack." ;;
    kubevirt) echo "KubeVirt — runs VMs as first-class Kubernetes workloads using KVM via virt-launcher pods; backbone of the vm-runtime capability." ;;
    kubevirt-cdi) echo "KubeVirt Containerized Data Importer — provides PVC import from URLs, registries, and uploads for VM disk images consumed by KubeVirt." ;;
    kyverno) echo "Kyverno policy engine — enforces PNI admission contract, reserved-label/annotation rules, and capability validation via ClusterPolicy CRs." ;;
    local-path-provisioner) echo "Rancher local-path-provisioner — provides a default StorageClass backed by node-local directories for non-replicated workloads." ;;
    loki) echo "Grafana Loki — log aggregation and query backend; the active implementation of the logs-storage and logs-query capabilities." ;;
    metrics-server) echo "Kubernetes Metrics Server — serves the resource metrics API (metrics.k8s.io) consumed by HorizontalPodAutoscaler and \`kubectl top\`." ;;
    multus-cni) echo "Multus CNI meta-plugin — lets pods attach to additional networks beyond the default CNI via NetworkAttachmentDefinition CRs." ;;
    node-feature-discovery) echo "Node Feature Discovery — labels nodes with detected hardware features (CPU flags, PCI devices, kernel modules) consumed by GPU/VM scheduling." ;;
    nvidia-dcgm-exporter) echo "NVIDIA DCGM Exporter — exposes per-GPU metrics (utilisation, memory, temperature) to Prometheus on GPU nodes." ;;
    nvidia-device-plugin) echo "NVIDIA Kubernetes Device Plugin — advertises GPU resources to the kubelet so workloads can request \`nvidia.com/gpu\`." ;;
    piraeus-operator) echo "Piraeus Operator — declarative LINSTOR + DRBD lifecycle; provides the block-storage-replicated capability (CSI driver \`linstor.csi.linbit.com\`)." ;;
    platform-network-interface) echo "Platform Network Interface (PNI) registry + Kyverno ClusterPolicies + Cilium CCNPs — the capability-first network-trust contract this base ships." ;;
    tetragon) echo "Cilium Tetragon — eBPF-based runtime security observability; emits TracingPolicy events for syscall and capability use." ;;
    vault-config-operator) echo "Vault Config Operator — manages Vault policies, auth-methods, and engine mounts via CRDs so secret configuration is GitOps-tracked." ;;
    vault-operator) echo "HashiCorp Vault server — KV/PKI/Transit secrets backend referenced by external-secrets, vault-config-operator, and cert-manager." ;;
    *) echo "Cluster-agnostic Helm base for $1." ;;
  esac
}

gotchas_of() {
  case "$1" in
    argocd) cat <<'GOTEOF'
- A bare `AppProject` (sync-wave -1) must reconcile before any Application (sync-wave 0) that references it.
- The base ships the ArgoCD chart and CRDs but not the root `Application` — consumer repos own that bootstrap.
GOTEOF
      ;;
    cert-manager) cat <<'GOTEOF'
- The `vault-ca` Secret is owned by cert-manager; the namespace carries `platform.io/vault-ca-distribution: skip` so the distribution policy does not clone it.
- Webhook port `10260` must be reachable from kube-apiserver — see Cilium's CCNP `ccnp-cert-manager-webhook`.
GOTEOF
      ;;
    kube-prometheus-stack) cat <<'GOTEOF'
- CRDs are shipped via `includeCRDs: true` in the Helm release — do not duplicate them in the consumer overlay.
- Loki and Tempo references in Grafana datasources are configured in the consumer overlay, not here.
GOTEOF
      ;;
    kyverno) cat <<'GOTEOF'
- Background scans are enabled and may take several minutes after install; `pni-instanced-suffix-required-audit` is the canonical audit-only policy.
- ClusterPolicy renames (e.g. `pni-contract-audit` → `pni-contract-enforce` in v0.4.0) break PolicyReport queries keyed on the old name; see UPGRADING.md.
GOTEOF
      ;;
    loki) cat <<'GOTEOF'
- The S3 endpoint is set in the consumer overlay, not the base `values.yaml` — base previously hardcoded a homelab MinIO endpoint, fixed in Phase 1.5.
GOTEOF
      ;;
    multus-cni) cat <<'GOTEOF'
- This is a resources-only component (no Helm chart) — installed from upstream daemonset YAML pinned in the kustomization.
GOTEOF
      ;;
    piraeus-operator) cat <<'GOTEOF'
- DRBD kernel module must be loaded on every storage node; Talos requires `kernelModules: ["drbd"]` in the machine-config patch (`talos/patches/drbd.yaml`).
- LinstorCluster + LinstorSatelliteConfiguration CRs are NOT shipped here; consumer overlay deploys them.
GOTEOF
      ;;
    platform-network-interface) cat <<'GOTEOF'
- Per-instance Kyverno generate/mutate rules (one CCNP per managed CR instance) are the consumer overlay's responsibility — see AGENTS.md §Out of scope for the base.
- All reserved label keys (`platform.io/provide.*`, `platform.io/capability-provider.*`) are listed in the Hard Constraints section of AGENTS.md.
GOTEOF
      ;;
    tetragon) cat <<'GOTEOF'
- TracingPolicy CRs default to `monitoring` namespace for the scrape endpoint; do not move the namespace without updating the CCNP.
GOTEOF
      ;;
    vault-operator) cat <<'GOTEOF'
- This is the *operator* (HelmRelease + CRDs), not a running Vault instance — the actual `Vault` CR is deployed by the consumer overlay because keys, unsealing strategy, and storage backend are per-cluster.
GOTEOF
      ;;
    vault-config-operator) cat <<'GOTEOF'
- Reads Vault root token from a Kubernetes Secret named `vault-config-operator-token` in this namespace — consumer overlay creates the Secret via External Secrets from Vault itself, a chicken-and-egg the consumer initialises by hand on Day-0.
GOTEOF
      ;;
    external-secrets) cat <<'GOTEOF'
- ClusterSecretStores referencing Vault are NOT shipped here — they live in the consumer overlay so per-cluster Vault endpoints, mounts, and auth-methods stay out of the base.
GOTEOF
      ;;
    *) echo "(none documented yet)" ;;
  esac
}

render_one() {
  local comp="$1"
  local dir="$INFRA_DIR/$comp"
  [ -d "$dir" ] || { echo "skip: $comp — no directory" >&2; return; }

  local purpose
  purpose="$(purpose_of "$comp")"
  local gotchas
  gotchas="$(gotchas_of "$comp")"

  local chart_block="This component is not Helm-based; it installs upstream YAML directly via kustomize."
  if [ -f "$dir/chart.lock.yaml" ]; then
    local repo name version
    repo="$(yq -r '.chart.repo' "$dir/chart.lock.yaml")"
    name="$(yq -r '.chart.name' "$dir/chart.lock.yaml")"
    version="$(yq -r '.chart.version' "$dir/chart.lock.yaml")"
    chart_block="- **Chart:** [\`$name\`]($repo)
- **Pinned version:** \`$version\`
- **Lock file:** [\`chart.lock.yaml\`](./chart.lock.yaml) — includes \`tgz_sha256\` for reproducible renders."
  fi

  local ns_name="(no namespace.yaml)"
  local provide_lines="(none)"
  local consume_lines="(none)"
  if [ -f "$dir/namespace.yaml" ]; then
    ns_name="$(yq -r '.metadata.name // "?"' "$dir/namespace.yaml")"
    provide_lines="$(yq -r '.metadata.labels // {} | to_entries[] | select(.key | test("^platform.io/provide\\.")) | "- `\(.key)`"' "$dir/namespace.yaml")"
    consume_lines="$(yq -r '.metadata.labels // {} | to_entries[] | select(.key | test("^platform.io/consume\\.")) | "- `\(.key)`"' "$dir/namespace.yaml")"
    [ -z "$provide_lines" ] && provide_lines="(none — this component does not declare a PNI provider role)"
    [ -z "$consume_lines" ] && consume_lines="(none — this component does not declare a PNI consumer role)"
  fi

  local values_block="(no values.yaml — component does not override defaults)"
  if [ -f "$dir/values.yaml" ]; then
    local keys
    keys="$(yq -r 'keys | .[]' "$dir/values.yaml" 2>/dev/null | sed 's/^/- `/; s/$/`/')"
    if [ -n "$keys" ]; then
      values_block="$keys"
    fi
  fi

  cat <<EOF > "$dir/README.md"
# \`$comp\`

**Purpose:** $purpose

## Upstream chart source

$chart_block

## Namespace

Deploys into namespace \`$ns_name\`. See [\`namespace.yaml\`](./namespace.yaml) for the full PSA + PNI label set.

## Declared PNI capabilities

**Provider labels** (on the namespace; see [ADR — Capability Producer/Consumer Symmetry](../../../../docs/adr-capability-producer-consumer-symmetry.md)):

$provide_lines

**Consumer labels:**

$consume_lines

For the full label vocabulary see [\`docs/capability-reference.md\`](../../../../docs/capability-reference.md).

## Repo-specific Helm-value overrides

Top-level keys in [\`values.yaml\`](./values.yaml) — anything not listed below uses the upstream chart's default:

$values_block

## Known upgrade gotchas

$gotchas

## See also

- [\`docs/rendered-manifests.md\`](../../../../docs/rendered-manifests.md) — how this component is rendered into \`_rendered/manifests.yaml\`
- [\`docs/capability-architecture.md\`](../../../../docs/capability-architecture.md) — capability-first contract overview
- [\`UPGRADING.md\`](../../../../UPGRADING.md) — release-to-release migration steps
EOF

  echo "wrote $dir/README.md"
}

mode="write"
single=""
case "${1:-}" in
  --check) mode="check" ;;
  --help|-h) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  "") ;;
  *) single="$1" ;;
esac

if [ "$mode" = "check" ]; then
  # Render to tmpdir, diff against committed.
  fails=0
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT
  while IFS= read -r comp; do
    [ -n "$comp" ] || continue
    target="$INFRA_DIR/$comp/README.md"
    if [ ! -f "$target" ]; then
      echo "missing: $target" >&2
      fails=$((fails + 1))
      continue
    fi
    INFRA_DIR_BACKUP="$INFRA_DIR"
    INFRA_DIR="$tmpdir"
    mkdir -p "$tmpdir/$comp"
    cp -R "$INFRA_DIR_BACKUP/$comp"/. "$tmpdir/$comp/"
    rm -f "$tmpdir/$comp/README.md"
    render_one "$comp" >/dev/null
    if ! diff -u "$target" "$tmpdir/$comp/README.md" >&2; then
      echo "drift: $target" >&2
      fails=$((fails + 1))
    fi
    INFRA_DIR="$INFRA_DIR_BACKUP"
  done < "$COMP_LIST"
  if [ "$fails" -gt 0 ]; then
    echo "ERROR: $fails README(s) out of date" >&2
    exit 1
  fi
  echo "OK: all 22 component READMEs match render"
  exit 0
fi

if [ -n "$single" ]; then
  render_one "$single"
  exit 0
fi

while IFS= read -r comp; do
  [ -n "$comp" ] || continue
  render_one "$comp"
done < "$COMP_LIST"
