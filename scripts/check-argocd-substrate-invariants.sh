#!/usr/bin/env bash
# Check substrate invariants in both base render paths; consumer overrides are out of scope.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "::error::not inside a git work-tree — run this from within the repository" >&2; exit 1; }
ARGOCD_DIR="${ROOT}/kubernetes/substrate/argocd"
LOCK="${ARGOCD_DIR}/chart.lock.yaml"
STEADY_VALUES="${ARGOCD_DIR}/values.yaml"
BOOTSTRAP_VALUES="${ROOT}/tofu/modules/talos-cluster/helm/argocd-values.yaml"
NETPOL_GATE="${ROOT}/scripts/check-argocd-network-policy-invariants.sh"

for t in helm yq; do
  command -v "$t" >/dev/null 2>&1 || { echo "::error::required tool not found on PATH: $t" >&2; exit 1; }
done
for f in "$LOCK" "$STEADY_VALUES" "$BOOTSTRAP_VALUES"; do
  [ -f "$f" ] || { echo "::error::required file missing: $f" >&2; exit 1; }
done
[ -x "$NETPOL_GATE" ] || { echo "::error::required gate missing or not executable: $NETPOL_GATE" >&2; exit 1; }

repo="$(yq -e '.chart.repo' "$LOCK")"       || { echo "::error::chart.lock.yaml missing .chart.repo" >&2; exit 1; }
name="$(yq -e '.chart.name' "$LOCK")"       || { echo "::error::chart.lock.yaml missing .chart.name" >&2; exit 1; }
version="$(yq -e '.chart.version' "$LOCK")" || { echo "::error::chart.lock.yaml missing .chart.version" >&2; exit 1; }
expected_sha="$(yq '.chart.tgz_sha256 // ""' "$LOCK")"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

case "$repo" in
  oci://*) helm pull "${repo}/${name}" --version "$version" --destination "$tmp" >/dev/null 2>"$tmp/pull.err" ;;
  *)       helm pull "$name" --repo "$repo" --version "$version" --destination "$tmp" >/dev/null 2>"$tmp/pull.err" ;;
esac || { echo "::error::helm pull failed for ${name}@${version} from ${repo}" >&2; sed 's/^/    /' "$tmp/pull.err" >&2; exit 2; }
tgz="$(ls -t "$tmp/${name}"-*.tgz 2>/dev/null | head -n1)"
[ -n "$tgz" ] && [ -f "$tgz" ] || { echo "::error::chart pull produced no tarball" >&2; exit 2; }

if [ -n "$expected_sha" ]; then
  actual_sha="$(shasum -a 256 "$tgz" | awk '{print $1}')"
  if [ "$actual_sha" != "$expected_sha" ]; then
    echo "::error::chart sha256 mismatch for ${name}@${version}: lock=${expected_sha} actual=${actual_sha} (upstream republish or chart.lock.yaml drift)" >&2
    exit 2
  fi
else
  echo "::warning::chart.lock.yaml has no tgz_sha256 for ${name}@${version} — supply-chain digest verification skipped; pin it for reproducible, tamper-evident renders" >&2
fi

violations=0

render() {
  local out="$1" values="$2"
  if ! helm template argocd "$tgz" --namespace argocd -f "$values" > "$out" 2>"$tmp/helm.err"; then
    echo "::error::helm template failed for ${values}" >&2
    sed 's/^/    /' "$tmp/helm.err" >&2
    exit 2
  fi
}

# assert_invariant <label> <render> <yq-expr> <violation-message>
assert_invariant() {
  local label="$1" render="$2" expr="$3" msg="$4" out rc
  # Capture yq errors before filtering: grep’s no-match status is not a parse failure.
  set +e
  yq e "$expr" "$render" > "$tmp/yqout" 2>"$tmp/yqerr"
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    echo "::error::[${label}] yq failed to evaluate an invariant (could not parse render)" >&2
    sed 's/^/    /' "$tmp/yqerr" >&2
    exit 2
  fi
  out="$(grep -vE '^(---|\.\.\.| *)$' "$tmp/yqout" || true)"
  if [ -n "$out" ]; then
    echo "::error::[${label}] ${msg}:" >&2
    printf '%s\n' "$out" | sort -u | sed 's/^/    /' >&2
    violations=1
  fi
}

check_path() {
  local label="$1" render="$2"
  assert_invariant "$label" "$render" \
    'select(.metadata.labels."app.kubernetes.io/component" == "dex-server" or .metadata.name == "argocd-dex-server") | .kind + "/" + (.metadata.name // "<no-name>")' \
    'I1 violated: bundled-Dex resource present (expected dex.enabled: false)'
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

# Require ConfigMap presence before asserting the absence of forbidden keys.
require_cm() {
  local label="$1" render="$2" cm="$3" anchor
  anchor="$(yq e "select(.kind == \"ConfigMap\" and .metadata.name == \"${cm}\") | .metadata.name" "$render" 2>/dev/null | grep -c "^${cm}\$" || true)"
  if [ "$anchor" -ne 1 ]; then
    echo "::error::[${label}] anchor: expected exactly one ${cm} ConfigMap in the render, found ${anchor} — the name-scoped invariant on it would pass vacuously; the chart render shape changed." >&2
    exit 2
  fi
}

check_no_url() {
  local label="$1" render="$2"
  require_cm "$label" "$render" argocd-cm
  assert_invariant "$label" "$render" \
    'select(.kind == "ConfigMap" and .metadata.name == "argocd-cm") | (.data // {}) | keys | .[] | select(. == "url")' \
    'I3 violated: argocd-cm carries a `url` key (expected configs.cm.url: "" — the consumer owns this value)'
}

check_no_url "steady-state"   "$tmp/steady.yaml"
check_no_url "bootstrap-seed" "$tmp/bootstrap.yaml"

check_netpol_floor() {
  local label="$1" render="$2" got=0
  "$NETPOL_GATE" "$label" "$render" || got=$?
  case "$got" in
    0) ;;
    3) violations=$((violations + 1)) ;;
    *) exit "$got" ;;
  esac
}

check_netpol_floor "steady-state"   "$tmp/steady.yaml"
check_netpol_floor "bootstrap-seed" "$tmp/bootstrap.yaml"

check_no_shipped_identity() {
  local label="$1" render="$2"
  require_cm "$label" "$render" argocd-rbac-cm
  assert_invariant "$label" "$render" \
    'select(.kind == "ConfigMap" and .metadata.name == "argocd-rbac-cm") | (.data."policy.csv" // "") | select(test("\\S"))' \
    'I4 violated: argocd-rbac-cm ships a non-empty policy.csv (the substrate ships no identity — the consumer owns their access policy; see knowledge/reference/argocd-sso-contract.md)'
}

check_no_shipped_identity "steady-state" "$tmp/steady.yaml"

check_no_default_role() {
  local label="$1" render="$2"
  require_cm "$label" "$render" argocd-rbac-cm
  assert_invariant "$label" "$render" \
    'select(.kind == "ConfigMap" and .metadata.name == "argocd-rbac-cm") | (.data."policy.default" // "") | select(test("\\S"))' \
    'I5 violated: argocd-rbac-cm ships a non-empty policy.default, which grants that role to EVERY authenticated principal in every consuming cluster — no subject required. The substrate floor is no-permission-by-default; a consumer widens it in their own overlay'
}

check_no_default_role "steady-state" "$tmp/steady.yaml"

MODULE_VARS="${ROOT}/tofu/modules/talos-cluster/variables.tf"
if [ -f "$MODULE_VARS" ]; then
  seed_version="$(awk '/^variable "argocd_chart_version"/ {inb=1} inb && /^[[:space:]]*default[[:space:]]*=/ {gsub(/.*=[[:space:]]*"/, ""); gsub(/".*/, ""); print; exit}' "$MODULE_VARS")"
  if [ -z "$seed_version" ]; then
    echo "::error::[chart-pin parity] could not read the default of variable \"argocd_chart_version\" from ${MODULE_VARS#"${ROOT}/"} — the parity check cannot run; re-point it." >&2
    exit 2
  fi
  if [ "$seed_version" != "$version" ]; then
    echo "::error::[chart-pin parity] the Day-0 seed renders argo-cd ${seed_version} (variables.tf argocd_chart_version) while the steady-state component pins ${version} (chart.lock.yaml). ArgoCD owns those CRDs after the first sync, and the Day-0 apply no longer forces conflicts — so a schema divergence fails every consumer's next \`tofu apply\`, not just the one that bumped. Bump both pins together." >&2
    violations=1
  fi
fi

# Use the SSO overlay as a differential control for opt-in settings.
EXAMPLE_DIR="${ROOT}/kubernetes/examples/argocd-consumer-sso"
# A missing SSO fixture must fail, not skip the control.
[ -f "${EXAMPLE_DIR}/kustomization.yaml" ] || {
  echo "::error::required file missing: ${EXAMPLE_DIR#"${ROOT}/"}/kustomization.yaml — the worked consumer-SSO overlay is what binds knowledge/reference/argocd-sso-contract.md to something buildable; without it E0-E5 would pass vacuously. Restore it, or remove this block deliberately." >&2
  exit 1
}
for t in kustomize kubeconform; do
  command -v "$t" >/dev/null 2>&1 || { echo "::error::required tool not found on PATH: $t (needed for the consumer-SSO overlay check)" >&2; exit 1; }
done

echo "==> building the consumer-SSO overlay and its unpatched control"
kustomize build "$ARGOCD_DIR"  > "$tmp/ctl-full.yaml" 2>"$tmp/kz.err" || {
  echo "::error::kustomize build failed for ${ARGOCD_DIR#"${ROOT}/"} (the control build)" >&2
  sed 's/^/    /' "$tmp/kz.err" >&2; exit 2; }
kustomize build "$EXAMPLE_DIR" > "$tmp/sso-full.yaml" 2>"$tmp/kz.err" || {
  echo "::error::kustomize build failed for ${EXAMPLE_DIR#"${ROOT}/"} — the documented consumer overlay no longer builds against the component it patches (knowledge/reference/argocd-sso-contract.md)" >&2
  sed 's/^/    /' "$tmp/kz.err" >&2; exit 2; }

# Check committed manifests separately from freshly rendered chart output.
check_netpol_floor "steady-state (kustomize build)" "$tmp/ctl-full.yaml"

for s in ctl sso; do
  yq e 'select(.kind == "ConfigMap" and (.metadata.name == "argocd-cm" or .metadata.name == "argocd-rbac-cm"))' \
    "$tmp/${s}-full.yaml" > "$tmp/${s}.yaml"
done

# Normalize absent and literal-null values before comparing ConfigMap data.
cm_data() {
  yq e "select(.kind == \"ConfigMap\" and .metadata.name == \"$2\") | .data $3" "$1" 2>/dev/null |
    sed 's/^null$//' || true
}

require_cm "consumer-sso/control" "$tmp/ctl.yaml" argocd-cm
require_cm "consumer-sso/control" "$tmp/ctl.yaml" argocd-rbac-cm
if [ "$(cm_data "$tmp/ctl.yaml" argocd-cm '| has("url")')" != "false" ] ||
   [ -n "$(cm_data "$tmp/ctl.yaml" argocd-cm '."oidc.config" // ""' | tr -d '[:space:]')" ] ||
   [ -n "$(cm_data "$tmp/ctl.yaml" argocd-rbac-cm '."policy.csv" // ""' | tr -d '[:space:]')" ]; then
  echo "::error::[consumer-sso] E0 control: the UNPATCHED component already carries a url, an oidc.config and/or a policy.csv, so E1-E3 below would prove nothing about the overlay. Fix the component, not this check." >&2
  exit 3
fi

if [ -z "$(cm_data "$tmp/sso.yaml" argocd-cm '.url // ""' | tr -d '[:space:]')" ]; then
  echo "::error::[consumer-sso] E1: the overlay does not produce a non-empty argocd-cm url — the documented SSO wiring no longer applies." >&2
  violations=1
fi

oidc="$(cm_data "$tmp/sso.yaml" argocd-cm '."oidc.config" // ""')"
if ! printf '%s\n' "$oidc" | yq e '.issuer // "" | select(. != "")' - >/dev/null 2>&1 ||
   [ -z "$(printf '%s\n' "$oidc" | yq e '.issuer // ""' - 2>/dev/null | tr -d '[:space:]')" ] ||
   [ -z "$(printf '%s\n' "$oidc" | yq e '.clientID // ""' - 2>/dev/null | tr -d '[:space:]')" ]; then
  echo "::error::[consumer-sso] E2: argocd-cm oidc.config does not parse as YAML carrying both issuer and clientID." >&2
  violations=1
fi

if [ -z "$(cm_data "$tmp/sso.yaml" argocd-rbac-cm '."policy.csv" // ""' | tr -d '[:space:]')" ]; then
  echo "::error::[consumer-sso] E3: the overlay does not produce a non-empty argocd-rbac-cm policy.csv." >&2
  violations=1
fi

for cm in argocd-cm argocd-rbac-cm; do
  missing="$(comm -23 \
    <(cm_data "$tmp/ctl.yaml" "$cm" '| keys | .[]' | sort -u) \
    <(cm_data "$tmp/sso.yaml" "$cm" '| keys | .[]' | sort -u))"
  if [ -n "$missing" ]; then
    echo "::error::[consumer-sso] E4: patching ${cm} DROPPED base-shipped .data keys — the patch replaces the map instead of merging into it:" >&2
    printf '%s\n' "$missing" | sed 's/^/    /' >&2
    violations=1
  fi
done

if ! kubeconform -strict -ignore-missing-schemas "$tmp/sso-full.yaml" >"$tmp/kc.out" 2>&1; then
  echo "::error::[consumer-sso] E5: the patched build fails kubeconform -strict" >&2
  sed 's/^/    /' "$tmp/kc.out" >&2
  violations=1
fi

if [ "$violations" -ne 0 ]; then
  echo "::error::ArgoCD substrate invariants FAILED (see above). Declared in kubernetes/substrate/argocd/README.md §Substrate invariants." >&2
  exit 3
fi
echo "OK: ArgoCD substrate invariants hold (I1-I3 + I6 in both render paths: no bundled Dex, no server.dex.server* cmd-params, no placeholder argocd-cm url, and the exact five-policy NetworkPolicy selector/ingress posture; I4/I5 steady-state: no shipped policy.csv, no blanket policy.default; P: seed and steady-state chart pins agree; E: the worked consumer-SSO overlay merges url/oidc.config/policy.csv in against a control build without dropping a base-shipped key)."
