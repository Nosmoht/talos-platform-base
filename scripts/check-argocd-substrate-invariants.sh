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
#   I3  No argocd-cm carries a `url` key (shared across both paths).
#   I4  No non-empty argocd-rbac-cm `policy.csv` (steady-state only).
#   I5  No non-empty argocd-rbac-cm `policy.default` (steady-state only) — wider
#       blast radius than I4, hence its own assertion.
#   I6  Both paths carry the exact five-policy NetworkPolicy posture: component
#       selectors, ingress peers/ports and policyTypes (shared across both).
#   P   The module's argocd_chart_version default equals chart.lock.yaml's
#       version. Load-bearing since the Day-0 apply stopped forcing conflicts.
#   E0-E5  The worked consumer-SSO overlay still wires the component, asserted
#       against an UNPATCHED control build of the same component.
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

# require_cm <label> <render> <configmap-name>
# Presence anchor for the name-scoped invariants below: a name-scoped NEGATIVE
# assertion passes vacuously if the chart renames or drops the ConfigMap it
# selects on. I1/I2 avoid this by scanning every document; I3/I4 cannot (they
# assert on generic key names — see below), so they need the anchor instead.
# Exit 2, not 3 — an absent ConfigMap is a render-shape problem, not a violated
# invariant, and the two must not be conflated in the exit code.
require_cm() {
  local label="$1" render="$2" cm="$3" anchor
  anchor="$(yq e "select(.kind == \"ConfigMap\" and .metadata.name == \"${cm}\") | .metadata.name" "$render" 2>/dev/null | grep -c "^${cm}\$" || true)"
  if [ "$anchor" -ne 1 ]; then
    echo "::error::[${label}] anchor: expected exactly one ${cm} ConfigMap in the render, found ${anchor} — the name-scoped invariant on it would pass vacuously; the chart render shape changed." >&2
    exit 2
  fi
}

# I3 — no placeholder Argo CD base URL. SHARED across both paths. The chart
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
check_no_url() {
  local label="$1" render="$2"
  require_cm "$label" "$render" argocd-cm
  assert_invariant "$label" "$render" \
    'select(.kind == "ConfigMap" and .metadata.name == "argocd-cm") | (.data // {}) | keys | .[] | select(. == "url")' \
    'I3 violated: argocd-cm carries a `url` key (expected configs.cm.url: "" — the consumer owns this value)'
}

check_no_url "steady-state"   "$tmp/steady.yaml"
check_no_url "bootstrap-seed" "$tmp/bootstrap.yaml"

# I6 — exact chart-emitted per-component NetworkPolicy posture, SHARED across
# both paths. The dedicated gate binds the five-policy anchor, each component's
# selector, ingress peers/ports and policyTypes. Its bite-check mutates the real
# committed render to prove empty/wrong selectors, open redis, a closed server
# and a vanished policy are all rejected.
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

# I4 — the substrate ships NO identity: argocd-rbac-cm carries no NON-EMPTY
# policy.csv. STEADY-STATE ONLY by construction, not by omission — the seed
# renders from the module values, which have never carried an RBAC policy, and
# the asymmetry that motivates I4 is steady-state-specific: the published
# component is what a consumer's overlay merges onto, so a principal shipped
# here becomes a standing grant in every consuming cluster.
#
# The assertion is on EMPTINESS, not absence: the chart's argocd-rbac-cm template
# emits policy.csv unconditionally, so `""` is the shipped state and a `has(key)`
# check would false-positive forever. Whitespace-only counts as empty — a policy
# of blank lines grants nothing, and rejecting it would gate formatting, not
# access.
check_no_shipped_identity() {
  local label="$1" render="$2"
  require_cm "$label" "$render" argocd-rbac-cm
  assert_invariant "$label" "$render" \
    'select(.kind == "ConfigMap" and .metadata.name == "argocd-rbac-cm") | (.data."policy.csv" // "") | select(test("\\S"))' \
    'I4 violated: argocd-rbac-cm ships a non-empty policy.csv (the substrate ships no identity — the consumer owns their access policy; see knowledge/reference/argocd-sso-contract.md)'
}

check_no_shipped_identity "steady-state" "$tmp/steady.yaml"

# I5 — argocd-rbac-cm ships no non-empty policy.default. Steady-state only, same
# construction argument as I4.
#
# Separate from I4 rather than folded into it, because policy.default has a
# strictly WIDER blast radius: a policy binds the subjects it names, while
# policy.default grants its role to EVERY authenticated principal in every
# consuming cluster, with no subject at all. Before this invariant the key with
# the smaller blast radius was gated and the larger one was not — the values file
# itself conceded "no gate asserts it".
check_no_default_role() {
  local label="$1" render="$2"
  require_cm "$label" "$render" argocd-rbac-cm
  assert_invariant "$label" "$render" \
    'select(.kind == "ConfigMap" and .metadata.name == "argocd-rbac-cm") | (.data."policy.default" // "") | select(test("\\S"))' \
    'I5 violated: argocd-rbac-cm ships a non-empty policy.default, which grants that role to EVERY authenticated principal in every consuming cluster — no subject required. The substrate floor is no-permission-by-default; a consumer widens it in their own overlay'
}

check_no_default_role "steady-state" "$tmp/steady.yaml"

# P — seed/steady-state chart-pin parity. Formerly "maintained by review, not
# mechanically gated" (component README §Deferred), which was tolerable while the
# Day-0 apply passed --force-conflicts: a divergence was silently steamrolled.
# It no longer is. The module renders the Day-0 CRDs at var.argocd_chart_version
# and ArgoCD owns the steady-state CRDs rendered at chart.lock.yaml's version; if
# the two pins drift, the un-forced server-side apply hits a schema conflict and
# FAILS `tofu apply` — for every consumer, on an unrelated apply. So the pin the
# safety argument silently assumes is now asserted.
#
# Version-string parity only. A same-version upstream republish (changed
# tgz_sha256) still slips through; the tarball digest check above covers the
# steady-state side of that, the module side is unpinned by design.
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

# --- E: the worked consumer-SSO overlay actually wires what the contract claims.
#
# I1-I6 assert what the base does NOT ship, or ships unweakened. That is only half the contract: the
# other half is that a consumer CAN supply the missing identity, through the
# documented mechanism, without losing the keys the base does ship. Documentation
# alone cannot hold that — a chart bump that renamed a ConfigMap, or a patch that
# silently stopped matching, would leave the prose confidently wrong.
#
# CONTROL RUN FIRST. Every assertion below is a comparison against the UNPATCHED
# build, not a bare property of the patched one. A one-sided check ("the merged
# argocd-cm has a url") passes identically whether the patch worked or the base
# started shipping a url again — the control is what makes it evidence.
#
# Built from the COMMITTED _rendered/ manifests via kustomize, i.e. the same
# artifact a consumer consumes, not the fresh helm render the invariants above
# use. That is deliberate: this asserts the consumer-facing mechanism.
EXAMPLE_DIR="${ROOT}/kubernetes/examples/argocd-consumer-sso"
# NOT `if [ -d ... ]`. A conditional that vanishes with its own input is the
# vacuous pass this script's require_cm anchor exists to refuse: delete or rename
# the example and E0-E5 would silently not run while the success line below still
# claimed they held. The example is a committed, spec-required input
# (openspec/specs/argocd-substrate: "SHALL bind it to a buildable worked
# overlay"), so it is treated like the values files — missing means exit 1.
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

# Reduce once. Both builds carry the ~29k-line CRD stream, and the E-series makes
# a dozen ConfigMap lookups; re-parsing the full stream per lookup is pure cost.
for s in ctl sso; do
  yq e 'select(.kind == "ConfigMap" and (.metadata.name == "argocd-cm" or .metadata.name == "argocd-rbac-cm"))' \
    "$tmp/${s}-full.yaml" > "$tmp/${s}.yaml"
done

# cm_data <render> <configmap-name> <yq-suffix>
# `// ""` inside the caller's suffix is not enough: yq prints the literal `null`
# for a missing key under an existing parent, and `null` survives a whitespace
# strip as a non-empty string — which would invert E0's diagnosis. Normalise it
# here, once, rather than at every call site.
cm_data() {
  yq e "select(.kind == \"ConfigMap\" and .metadata.name == \"$2\") | .data $3" "$1" 2>/dev/null |
    sed 's/^null$//' || true
}

# E0 — the control genuinely lacks everything the patch is claimed to add.
# Without it, E1/E2/E3 would pass unchanged if the base regressed to shipping
# those values, which is the one-sided failure this whole block exists to avoid.
# oidc.config is in here too: E2 has no other control, so omitting it would leave
# exactly one assertion proving nothing.
require_cm "consumer-sso/control" "$tmp/ctl.yaml" argocd-cm
require_cm "consumer-sso/control" "$tmp/ctl.yaml" argocd-rbac-cm
if [ "$(cm_data "$tmp/ctl.yaml" argocd-cm '| has("url")')" != "false" ] ||
   [ -n "$(cm_data "$tmp/ctl.yaml" argocd-cm '."oidc.config" // ""' | tr -d '[:space:]')" ] ||
   [ -n "$(cm_data "$tmp/ctl.yaml" argocd-rbac-cm '."policy.csv" // ""' | tr -d '[:space:]')" ]; then
  echo "::error::[consumer-sso] E0 control: the UNPATCHED component already carries a url, an oidc.config and/or a policy.csv, so E1-E3 below would prove nothing about the overlay. Fix the component, not this check." >&2
  exit 3
fi

# E1 — the overlay supplies the base URL.
if [ -z "$(cm_data "$tmp/sso.yaml" argocd-cm '.url // ""' | tr -d '[:space:]')" ]; then
  echo "::error::[consumer-sso] E1: the overlay does not produce a non-empty argocd-cm url — the documented SSO wiring no longer applies." >&2
  violations=1
fi

# E2 — and an oidc.config that PARSES and carries the two fields without which
# the connector cannot be constructed. A syntactically broken block would
# otherwise satisfy a mere presence check.
oidc="$(cm_data "$tmp/sso.yaml" argocd-cm '."oidc.config" // ""')"
if ! printf '%s\n' "$oidc" | yq e '.issuer // "" | select(. != "")' - >/dev/null 2>&1 ||
   [ -z "$(printf '%s\n' "$oidc" | yq e '.issuer // ""' - 2>/dev/null | tr -d '[:space:]')" ] ||
   [ -z "$(printf '%s\n' "$oidc" | yq e '.clientID // ""' - 2>/dev/null | tr -d '[:space:]')" ]; then
  echo "::error::[consumer-sso] E2: argocd-cm oidc.config does not parse as YAML carrying both issuer and clientID." >&2
  violations=1
fi

# E3 — and the RBAC policy the consumer owns.
if [ -z "$(cm_data "$tmp/sso.yaml" argocd-rbac-cm '."policy.csv" // ""' | tr -d '[:space:]')" ]; then
  echo "::error::[consumer-sso] E3: the overlay does not produce a non-empty argocd-rbac-cm policy.csv." >&2
  violations=1
fi

# E4 — strategic merge, not replacement. A JSON6902 patch or a `$patch: replace`
# silently drops every base-shipped key (kustomize.buildOptions,
# resource.exclusions, the compare options) while E1-E3 still pass. This is the
# failure the contract warns about, so it gets a mechanical check.
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

# E5 — and the result is still valid Kubernetes.
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
