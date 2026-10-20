#!/usr/bin/env bash
# Fail when a covered line's newest Talos release leaves the baseline coredns-seed.tf copies,
# or its golden CoreDNS objects differ from the seed in a copied field (ADR-0031). NETWORK.
# Usage: scripts/check-coredns-builtin-parity.sh [talos_tag ...]
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "${ROOT}"

BASELINE="scripts/fixtures/coredns-builtin-parity.txt"
LINES_FILE="scripts/fixtures/talos-supported-lines.txt"
SEED="tofu/modules/talos-cluster/coredns-seed.tf"
VARIABLES="tofu/modules/talos-cluster/variables.tf"
ORACLES="tofu/modules/talos-cluster/tests/coredns-seed.tftest.hcl"
REPO="https://github.com/siderolabs/talos"
TEMPLATES="internal/app/machined/pkg/controllers/k8s/internal/k8stemplates"
CONSTANTS="pkg/machinery/constants/constants.go"
CONTROL_PLANE="internal/app/machined/pkg/controllers/k8s/control_plane.go"
DNS_ADDRS="pkg/machinery/resources/k8s/k8s.go"
DNS_IPS_LEGACY="pkg/machinery/config/types/v1alpha1/v1alpha1_clusterconfig.go"

fail() {
  echo "::error::check-coredns-builtin-parity: $*" >&2
  exit 1
}
envfail() {
  echo "check-coredns-builtin-parity: $*" >&2
  exit 2
}

for tool in curl git awk sed sort diff shasum tofu jq yq; do
  command -v "${tool}" >/dev/null || envfail "${tool} not installed"
done
for file in "${BASELINE}" "${LINES_FILE}" "${ORACLES}"; do
  [ -f "${file}" ] || envfail "${file} missing"
done

ROWS="$(awk '/^[[:space:]]*(#|$)/ {next} !/^v[0-9]+\.[0-9]+ v[0-9]+\.[0-9]+\.[0-9]+ v[0-9]+\.[0-9]+\.[0-9]+$/ || index($2, $1 ".") != 1 {print "unsupported row " NR ": " $0 > "/dev/stderr"; bad = 1; next} {print} END {exit bad}' "${LINES_FILE}")" ||
  fail "every row of ${LINES_FILE} must read '<vMAJOR.MINOR> <a Talos release of that line> <a Kubernetes release>'"
supported_lines() { printf '%s\n' "${ROWS}"; }

newest_pin="$(supported_lines | tail -1 | awk '{print $2}')"
newest_k8s="$(supported_lines | tail -1 | awk '{print $3}')"
cited="$(grep -oE 'siderolabs/talos v[0-9]+\.[0-9]+\.[0-9]+' "${ORACLES}" | sort -u | awk '{print $2}' | paste -sd' ' -)"
[ "${cited}" = "${newest_pin}" ] ||
  fail "the oracle citations in ${ORACLES} name '${cited}', but the newest pin in ${LINES_FILE} is ${newest_pin}; re-derive the oracles from ${newest_pin} and cite it"

latest_release() {
  local line="$1" tags
  tags="$(git ls-remote --tags --refs "${REPO}.git" "refs/tags/${line}.*")" ||
    envfail "cannot list the ${line} tags of ${REPO}"
  printf '%s\n' "${tags}" | sed -nE "s#.*refs/tags/(${line//./\\.}\.[0-9]+)\$#\1#p" | sort -t. -k3,3n | tail -1
}

if [ "$#" -gt 0 ]; then
  TAGS=("$@")
else
  TAGS=()
  while read -r line _; do
    tag="$(latest_release "${line}")"
    [ -n "${tag}" ] || envfail "no release tag found for the supported line ${line}"
    TAGS+=("${tag}")
  done < <(supported_lines)
fi

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# fetch <tag> <path> <dest>: 0 fetched, 1 absent at that tag; any other failure is environmental.
fetch() {
  local code
  code="$(curl -sSL --retry 3 -o "$3" -w '%{http_code}' "https://raw.githubusercontent.com/siderolabs/talos/$1/$2")" ||
    envfail "cannot fetch $2 at $1"
  case "${code}" in
    200) return 0 ;;
    404) return 1 ;;
    *) envfail "fetching $2 at $1 returned HTTP ${code}" ;;
  esac
}

# The seed as Talos receives it: the manifest text the module renders, decoded by yq.
render_seed() {
  local name="$1" extra="$2"
  cat >"${WORK}/${name}.tfvars" <<EOF
cluster_name = "parity"
cluster_endpoint = "https://192.0.2.1:6443"
talos_version = "${newest_pin}"
kubernetes_version = "${newest_k8s}"
coredns_node_separation = true
images = { intel = { architecture = "amd64", cpu_vendor = "intel", extensions = [] } }
nodes = {
  cp = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] }
  worker-1 = { ip = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = [] }
  worker-2 = { ip = "192.0.2.13", role = "worker", image = "intel", hardware_capabilities = [] }
}
${extra}
EOF
  printf '%s\n' 'jsonencode(local.coredns_manifest)' |
    tofu -chdir="${WORK}/module" console -var-file="${WORK}/${name}.tfvars" >"${WORK}/${name}.console" 2>&1 ||
    fail "the seed render failed: $(cat "${WORK}/${name}.console")"
  jq -r . "${WORK}/${name}.console" | jq -r . | yq ea -o=json -I=0 '[.]' >"${WORK}/${name}.json" ||
    fail "the rendered seed manifest does not decode as YAML"
}

# Upstream golden files of the built-in objects (MPL-2.0, compared at run time only) and the
# seed object each is compared with, by kind and seed render.
GOLDEN="${TEMPLATES}/testdata"
GOLDEN_PAIRS=(
  "coredns-service-account ServiceAccount seed-single"
  "coredns-cluster-role ClusterRole seed-single"
  "coredns-cluster-role-binding ClusterRoleBinding seed-single"
  "coredns-configmap-cluster-domain ConfigMap seed-single"
  "coredns-deployment Deployment seed-single"
  "coredns-service-ipv4 Service seed-single"
  "coredns-service-dual Service seed-dual"
)

# Left out as seed-owned: recommended labels, pod anti-affinity, image (default-image line),
# the golden IPv6 test address (dns-service-address section), and a node affinity the line lacks.
# shellcheck disable=SC2016
JQ_DEFS='
def seed_labels: with_entries(select(.key | startswith("app.kubernetes.io/") | not));
def tidy:
  del(.status, .metadata.creationTimestamp, .spec.template.metadata.creationTimestamp)
  | if .metadata.labels then .metadata.labels |= seed_labels else . end
  | if .metadata.labels == {} then del(.metadata.labels) else . end
  | if .spec.template.metadata.labels then .spec.template.metadata.labels |= seed_labels else . end
  | if .kind == "Deployment" then
      del(.spec.template.spec.affinity.podAntiAffinity)
      | .spec.template.spec.containers |= map(del(.image))
      | if $no_node_affinity then del(.spec.template.spec.affinity.nodeAffinity) else . end
      | if .spec.template.spec.affinity == {} then del(.spec.template.spec.affinity) else . end
    else . end
  | if .kind == "Service" and ((.spec.clusterIPs // []) | length) > 1 then .spec.clusterIPs[1] = "<IPv6 DNS service address>" else . end;
'

compare_golden() {
  local tag="$1" dir="$2" no_node_affinity="$3" pair file kind seed failed=""
  for pair in "${GOLDEN_PAIRS[@]}"; do
    read -r file kind seed <<<"${pair}"
    fetch "${tag}" "${GOLDEN}/${file}.yaml" "${dir}/${file}.yaml" || fail "${GOLDEN}/${file}.yaml is gone at ${tag}"
    yq -o=json '.' "${dir}/${file}.yaml" |
      jq -S --argjson no_node_affinity "${no_node_affinity}" "${JQ_DEFS} tidy" >"${dir}/${file}.golden.json" ||
      fail "${GOLDEN}/${file}.yaml at ${tag} does not decode as YAML"
    jq -S --arg kind "${kind}" --argjson no_node_affinity "${no_node_affinity}" \
      "${JQ_DEFS}"' [.[] | select(.kind == $kind)] | if length == 1 then .[0] | tidy else error("the seed carries \(length) objects of kind \($kind)") end' \
      "${WORK}/${seed}.json" >"${dir}/${file}.seed.json" || fail "the seed carries no single ${kind}"
    diff -u --label "Talos ${tag} ${file}.yaml" --label "seed ${kind} (${seed})" \
      "${dir}/${file}.golden.json" "${dir}/${file}.seed.json" >"${dir}/${file}.diff" ||
      failed="${failed}$(cat "${dir}/${file}.diff")
"
  done
  [ -z "${failed}" ] ||
    fail "the seed differs from the Talos ${tag} built-in in a copied field; bring ${SEED} in line, or name the field as seed-owned in this script and in ADR-0031:
${failed}"
}

mkdir -p "${WORK}/module"
cp tofu/modules/talos-cluster/*.tf tofu/modules/talos-cluster/.terraform.lock.hcl "${WORK}/module/"
cp -R tofu/modules/talos-cluster/helm tofu/modules/talos-cluster/manifests "${WORK}/module/"
tofu -chdir="${WORK}/module" init -input=false -no-color >"${WORK}/init.log" 2>&1 ||
  envfail "tofu init of the module copy failed: $(cat "${WORK}/init.log")"
render_seed seed-single ''
render_seed seed-dual $'dual_stack = true\npod_cidr = ["10.244.0.0/16", "fd00:10::/56"]\nservice_cidr = ["10.96.0.0/12", "fd00::/108"]'

# The facts the seed copies, one line each, as digests: the upstream text is MPL-2.0 and
# stays out of this repository. An empty extraction means the source moved.
section() {
  local name="$1" body
  body="$(cat)"
  if [ -z "${body}" ]; then
    printf '%s MISSING\n' "${name}"
  else
    printf '%s %s\n' "${name}" "$(printf '%s\n' "${body}" | shasum -a 256 | cut -d' ' -f1)"
  fi
}

go_block() { awk -v start="$1" 'index($0, start) == 1 {on = 1} on {print} on && /^}$/ {exit}' "$2"; }

# The meta/v1 import alias differs between lines and carries no field.
normalise() { sed -E 's/(^|[^A-Za-z0-9_])metav1\./\1v1./g'; }

extract() {
  local dir="$1" priority
  { grep -E '^[[:space:]]+(Kind|Name|Namespace):[[:space:]]+"' "${dir}/coredns.go" || :; } | sed -E 's/^[[:space:]]+//' | section identities
  { grep -E '^[[:space:]]+(APIGroups|Resources|Verbs):[[:space:]]+\[\]string' "${dir}/coredns.go" || :; } | sed -E 's/^[[:space:]]+//' | section rbac
  awk '/coreDNSConfig := fmt.Sprintf\(`/{on=1} on{print} /^}$/ && on && seen{exit} /loadbalance/{seen=1}' "${dir}/coredns.go" | section corefile
  go_block 'func CoreDNSService(' "${dir}/coredns.go" | normalise | section service
  priority="$(sed -nE 's/^const SystemClusterCriticalPriorityClassName = ("[^"]+")$/\1/p' "${dir}/k8stemplates.go")"
  go_block 'func CoreDNSDeployment(' "${dir}/coredns.go" | normalise |
    sed -E "s/SystemClusterCriticalPriorityClassName/${priority:-SystemClusterCriticalPriorityClassName}/" | section deployment
  if [ -f "${dir}/affinity.go" ]; then
    go_block 'var nodeAffinity = ' "${dir}/affinity.go" | section node-affinity
  else
    printf 'node-affinity absent\n'
  fi
  if grep -q '^var SupportedArchitectures = ' "${dir}/constants.go"; then
    go_block 'var SupportedArchitectures = ' "${dir}/constants.go" | section architectures
  else
    printf 'architectures absent\n'
  fi
  {
    awk '/dnsServiceIPs(, err)? :?= /{on = 1} on {print} on && /range dnsServiceIPs/ {loop = 1; match($0, /^[[:space:]]*/); indent = substr($0, 1, RLENGTH)} loop && $0 == indent "}" {exit}' "${dir}/control_plane.go"
    if [ -f "${dir}/k8s.go" ] && grep -q '^func DNSServiceAddrs(' "${dir}/k8s.go"; then
      go_block 'func DNSServiceAddrs(' "${dir}/k8s.go"
    else
      go_block 'func (c *ClusterConfig) DNSServiceIPs()' "${dir}/v1alpha1_clusterconfig.go"
    fi
  } | section dns-service-address
  printf 'default-image %s:%s\n' \
    "$(sed -nE 's/^[[:space:]]+CoreDNSImage = "([^"]+)"$/\1/p' "${dir}/constants.go")" \
    "$(sed -nE 's/^[[:space:]]+DefaultCoreDNSVersion = "([^"]+)"$/\1/p' "${dir}/constants.go")"
}

# A baseline key without a suffix holds for every line; key@vX.Y holds for that line only.
expected_for() {
  awk -v line="$1" '
    /^[[:space:]]*(#|$)/ {next}
    {key = $1; at = index(key, "@")}
    at == 0 {print; next}
    substr(key, at + 1) == line {print substr(key, 1, at - 1), $2}
  ' "${BASELINE}" | sort
}

for tag in "${TAGS[@]}"; do
  line="${tag%.*}"
  dir="${WORK}/${tag}"
  mkdir -p "${dir}"
  fetch "${tag}" "${TEMPLATES}/coredns.go" "${dir}/coredns.go" || fail "${TEMPLATES}/coredns.go is gone at ${tag}"
  fetch "${tag}" "${TEMPLATES}/k8stemplates.go" "${dir}/k8stemplates.go" || : >"${dir}/k8stemplates.go"
  fetch "${tag}" "${TEMPLATES}/affinity.go" "${dir}/affinity.go" || rm -f "${dir}/affinity.go"
  fetch "${tag}" "${CONSTANTS}" "${dir}/constants.go" || fail "${CONSTANTS} is gone at ${tag}"
  fetch "${tag}" "${CONTROL_PLANE}" "${dir}/control_plane.go" || fail "${CONTROL_PLANE} is gone at ${tag}"
  fetch "${tag}" "${DNS_ADDRS}" "${dir}/k8s.go" || rm -f "${dir}/k8s.go"
  fetch "${tag}" "${DNS_IPS_LEGACY}" "${dir}/v1alpha1_clusterconfig.go" || : >"${dir}/v1alpha1_clusterconfig.go"
  extract "${dir}" | sort >"${dir}/actual.txt"
  expected_for "${line}" >"${dir}/expected.txt"
  diff -u "${dir}/expected.txt" "${dir}/actual.txt" >"${dir}/sections.diff" ||
    fail "the Talos ${tag} built-in CoreDNS differs from ${BASELINE} (line ${line}) in the sections below; compare ${REPO}/tree/${tag}/${TEMPLATES}/coredns.go and the DNS service address derivation with ${SEED}, then refresh the baseline:
$(cat "${dir}/sections.diff")"
  if grep -qx 'node-affinity absent' "${dir}/expected.txt"; then
    compare_golden "${tag}" "${dir}" true
  else
    compare_golden "${tag}" "${dir}" false
  fi
done

image="$(sed -nE 's/^default-image (.+)$/\1/p' "${BASELINE}")"
grep -qE "^[[:space:]]+default[[:space:]]+= \"${image}\"$" "${VARIABLES}" ||
  fail "coredns_image in ${VARIABLES} does not default to the Talos default ${image}"

echo "check-coredns-builtin-parity: OK — the built-in CoreDNS of ${TAGS[*]} matches ${BASELINE} and, field by field, the seed's copied objects; coredns_image defaults to ${image}, and the test oracles cite ${newest_pin}."
