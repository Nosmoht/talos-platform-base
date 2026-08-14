#!/usr/bin/env bash
# check-argocd-substrate-invariants.sh — gate the shared ArgoCD substrate
# invariants across BOTH render paths so they cannot drift silently:
#   - Day-0 bootstrap seed   : tofu/modules/talos-cluster/helm/argocd-values.yaml
#   - steady-state self-mgmt : kubernetes/substrate/argocd/values.yaml
#
# The declared source-of-truth for these invariants is
# kubernetes/substrate/argocd/README.md §Substrate invariants.
# Invariants asserted here:
#   I1  No bundled-Dex resource: no rendered document carries the label
#       app.kubernetes.io/component=dex-server (nor metadata.name
#       "argocd-dex-server"). The label anchor survives a fullnameOverride and
#       also catches a dex.config-auto-enabled Dex (verified: setting
#       configs.cm.dex.config emits the same labelled workload).
#   I2  No ConfigMap has a .data key prefixed "server.dex.server" (scanning
#       every ConfigMap, not just argocd-cmd-params-cm by name, is rename-proof).
#       NB: argocd-server legitimately keeps optional configMapKeyRef *consumers*
#       naming these keys — those are env refs, not ConfigMap .data keys, and are
#       NOT a violation (a naïve `grep server.dex.server` would match them).
#
# Both base-shipped values files are rendered FRESH with the pinned argo-cd chart
# (kubernetes/substrate/argocd/chart.lock.yaml — the single version
# source) and asserted structurally. This is a values-property check ("does this
# values file disable the bundled Dex"), NOT a byte-reproduction of the tofu
# inlineManifest: the dex templates are gated on `dex.enabled`, not on K8s API
# capabilities, so the helm-CLI render and the helm-provider render agree on it,
# and no --kube-version is needed. CRDs are not rendered (irrelevant to the dex
# invariant; the bootstrap path also sets include_crds=false).
#
# OUT OF SCOPE: consumer var.argocd_values_override (merged over the bootstrap
# values at apply time) — base CI cannot gate what a consumer boots; consumer-
# cluster Kyverno owns that (AGENTS.md §ADR-0009).
#
# Exit codes:
#   0  both paths satisfy all invariants
#   1  usage / precondition (missing tool or input file)
#   2  render or parse error (could not produce/parse a manifest to assert on)
#   3  invariant violated
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "::error::not inside a git work-tree — run this from within the repository" >&2; exit 1; }
ARGOCD_DIR="${ROOT}/kubernetes/substrate/argocd"
LOCK="${ARGOCD_DIR}/chart.lock.yaml"
STEADY_VALUES="${ARGOCD_DIR}/values.yaml"
BOOTSTRAP_VALUES="${ROOT}/tofu/modules/talos-cluster/helm/argocd-values.yaml"

for t in helm yq; do
  command -v "$t" >/dev/null 2>&1 || { echo "::error::required tool not found on PATH: $t" >&2; exit 1; }
done
for f in "$LOCK" "$STEADY_VALUES" "$BOOTSTRAP_VALUES"; do
  [ -f "$f" ] || { echo "::error::required file missing: $f" >&2; exit 1; }
done

repo="$(yq -e '.chart.repo' "$LOCK")"       || { echo "::error::chart.lock.yaml missing .chart.repo" >&2; exit 1; }
name="$(yq -e '.chart.name' "$LOCK")"       || { echo "::error::chart.lock.yaml missing .chart.name" >&2; exit 1; }
version="$(yq -e '.chart.version' "$LOCK")" || { echo "::error::chart.lock.yaml missing .chart.version" >&2; exit 1; }
expected_sha="$(yq '.chart.tgz_sha256 // ""' "$LOCK")"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Pull the pinned chart once; template both values files from the same tarball.
case "$repo" in
  oci://*) helm pull "${repo}/${name}" --version "$version" --destination "$tmp" >/dev/null 2>"$tmp/pull.err" ;;
  *)       helm pull "$name" --repo "$repo" --version "$version" --destination "$tmp" >/dev/null 2>"$tmp/pull.err" ;;
esac || { echo "::error::helm pull failed for ${name}@${version} from ${repo}" >&2; sed 's/^/    /' "$tmp/pull.err" >&2; exit 2; }
tgz="$(ls -t "$tmp/${name}"-*.tgz 2>/dev/null | head -n1)"
[ -n "$tgz" ] && [ -f "$tgz" ] || { echo "::error::chart pull produced no tarball" >&2; exit 2; }

# Verify the pulled tarball against the lock's pinned digest (same supply-chain
# posture as render-component.sh) — a same-version upstream republish or a
# poisoned index would otherwise flow straight into the render the gate trusts.
if [ -n "$expected_sha" ]; then
  actual_sha="$(shasum -a 256 "$tgz" | awk '{print $1}')"
  if [ "$actual_sha" != "$expected_sha" ]; then
    echo "::error::chart sha256 mismatch for ${name}@${version}: lock=${expected_sha} actual=${actual_sha} (upstream republish or chart.lock.yaml drift)" >&2
    exit 2
  fi
else
  # Surface a missing pin instead of silently skipping verification (review L2):
  # an unpinned tarball is rendered un-tamper-checked, so make the gap visible.
  echo "::warning::chart.lock.yaml has no tgz_sha256 for ${name}@${version} — supply-chain digest verification skipped; pin it for reproducible, tamper-evident renders" >&2
fi

violations=0

# render <out> <values-file>
render() {
  local out="$1" values="$2"
  if ! helm template argocd "$tgz" --namespace argocd -f "$values" > "$out" 2>"$tmp/helm.err"; then
    echo "::error::helm template failed for ${values}" >&2
    sed 's/^/    /' "$tmp/helm.err" >&2
    exit 2
  fi
}

# assert_invariant <label> <render> <yq-expr> <violation-msg>
# The yq expr emits one line per offending item and nothing when the invariant
# holds. A non-zero yq exit means the render could not be parsed (script error,
# exit 2) — distinct from "expr matched" (invariant violated, recorded).
assert_invariant() {
  local label="$1" render="$2" expr="$3" msg="$4" out rc
  # `yq e` evaluates per-document (one line per matching doc); a clean render
  # yields no output. Capture yq's exit code directly (a parse failure → render
  # error, exit 2) BEFORE filtering, so it is never conflated with grep's
  # no-match exit. `---` document separators in the result are cosmetic.
  set +e
  yq e "$expr" "$render" > "$tmp/yqout" 2>"$tmp/yqerr"
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    echo "::error::[${label}] yq failed to evaluate an invariant (could not parse render)" >&2
    sed 's/^/    /' "$tmp/yqerr" >&2
    exit 2
  fi
  # Strip YAML document-stream artifacts (---, ..., blank lines) that yq emits
  # between scalar results; only real hits remain, so [ -n "$out" ] is sound.
  out="$(grep -vE '^(---|\.\.\.| *)$' "$tmp/yqout" || true)"
  if [ -n "$out" ]; then
    echo "::error::[${label}] ${msg}:" >&2
    printf '%s\n' "$out" | sort -u | sed 's/^/    /' >&2
    violations=1
  fi
}

check_path() {
  local label="$1" render="$2"
  # I1 — no bundled-Dex resource (label-anchored, OR the literal name).
  assert_invariant "$label" "$render" \
    'select(.metadata.labels."app.kubernetes.io/component" == "dex-server" or .metadata.name == "argocd-dex-server") | .kind + "/" + (.metadata.name // "<no-name>")' \
    'I1 violated: bundled-Dex resource present (expected dex.enabled: false)'
  # I2 — NO ConfigMap carries a server.dex.server* data key. Scanning every
  # ConfigMap (not just argocd-cmd-params-cm by name) is rename-proof: a chart
  # that renamed/moved the cmd-params CM cannot make the check pass vacuously.
  # `[.]` matches a literal dot unambiguously regardless of yq escape semantics.
  assert_invariant "$label" "$render" \
    'select(.kind == "ConfigMap") | .metadata.name as $n | (.data // {}) | keys | .[] | select(test("^server[.]dex[.]server")) | $n + " :: " + .' \
    'I2 violated: a ConfigMap has a server.dex.server* data key (bundled-Dex param leak)'
}

echo "==> argo-cd chart pin (chart.lock.yaml): ${name}@${version} from ${repo}"
echo "==> rendering steady-state values (${STEADY_VALUES#"${ROOT}/"})"
render "$tmp/steady.yaml" "$STEADY_VALUES"
echo "==> rendering bootstrap-seed values (${BOOTSTRAP_VALUES#"${ROOT}/"})"
render "$tmp/bootstrap.yaml" "$BOOTSTRAP_VALUES"

check_path "steady-state"   "$tmp/steady.yaml"
check_path "bootstrap-seed" "$tmp/bootstrap.yaml"

# I3 — no placeholder Argo CD base URL. PATH-SCOPED, not shared: it holds for the
# bootstrap seed today and extends to the steady-state render with #219. The chart
# derives configs.cm.url from global.domain, whose default is a placeholder
# hostname; ArgoCD documents `url` as required for SSO and derives the OIDC
# redirect URI from it, so a placeholder does not fail loudly — it fails at the
# IdP, at a human's first login. Absent is the visible state; the consumer
# supplies the real value in their overlay.
#
# Scanning by ConfigMap name is deliberate here (unlike I2's rename-proof sweep):
# `url` is a generic key that other ConfigMaps legitimately carry, so a blanket
# key scan would false-positive. argocd-notifications-cm's `argocdUrl` is a KNOWN,
# accepted residual — the chart renders it via `default (printf ...)`, and Helm's
# `default` treats "" as unset, so it cannot be cleared without disabling the
# whole notifications workload. See the component README §Substrate invariants.
assert_invariant "bootstrap-seed" "$tmp/bootstrap.yaml" \
  'select(.kind == "ConfigMap" and .metadata.name == "argocd-cm") | (.data // {}) | keys | .[] | select(. == "url")' \
  'I3 violated: argocd-cm carries a `url` key (expected configs.cm.url: "" — the consumer owns this value)'

if [ "$violations" -ne 0 ]; then
  echo "::error::ArgoCD substrate invariants FAILED (see above). Declared in kubernetes/substrate/argocd/README.md §Substrate invariants." >&2
  exit 3
fi
echo "OK: ArgoCD substrate invariants hold (bundled Dex disabled + no server.dex.server* cmd-params in both paths; no placeholder argocd-cm url in the bootstrap seed)."
