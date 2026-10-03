#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
for tool in tofu talosctl python3; do
  command -v "${tool}" >/dev/null || exit 2
done
umask 077
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
cp "${ROOT}/tofu/modules/talos-cluster/"*.tf "${WORK}/"
cp "${ROOT}/tofu/modules/talos-cluster/.terraform.lock.hcl" "${WORK}/"
mkdir "${WORK}/render"
cp "${ROOT}/tofu/modules/talos-cluster/tests/fixtures/provider-document-kinds/"*.tf "${WORK}/render/"
cp "${ROOT}/tofu/modules/talos-cluster/.terraform.lock.hcl" "${WORK}/render/"
cat >"${WORK}/render/validation.tf" <<'EOF'
variable "allow_scheduling" { type = bool }
locals {
  validation_documents = [for chunk in local.chunks : yamldecode(chunk)]
  native = startswith(var.talos_version, "v1.14.")
  kube_node = try([for doc in local.validation_documents : doc if try(doc.kind, "") == "KubeNodeConfig"][0], null)
  kubelet = try([for doc in local.validation_documents : doc if try(doc.kind, "") == "KubeletConfig"][0], null)
  proxy = try([for doc in local.validation_documents : doc if try(doc.kind, "") == "KubeProxyConfig"][0], null)
  legacy = yamldecode(local.v1alpha1)
}
output "validation_checks" {
  value = {
    installer = try([for doc in local.validation_documents : doc if try(doc.kind, "") == "UnattendedInstallConfig"][0].installer.image, local.legacy.machine.install.image, "") == "factory.talos.dev/metal-installer/fixture:v1.14.2"
    disk_selection = local.native ? try([for doc in local.validation_documents : doc if try(doc.kind, "") == "UnattendedInstallConfig"][0].provisioning.diskSelector.match == "disk.dev_path == \"/dev/vda\"", false) : true
    hostname = try([for doc in local.validation_documents : doc if try(doc.kind, "") == "HostnameConfig"][0].hostname, "") == (var.machine_type == "controlplane" ? "cp" : "worker")
    substrate_seeds = alltrue([for name in ["cilium", "argocd", "argocd-sops-age-key"] : local.native ? contains([for doc in local.validation_documents : try(doc.name, "") if try(doc.kind, "") == "KubeInlineManifestConfig"], name) == (var.machine_type == "controlplane") : contains([for manifest in try(local.legacy.cluster.inlineManifests, []) : manifest.name], name) == (var.machine_type == "controlplane")])
    rotation = try(local.kubelet.config.serverTLSBootstrap, local.legacy.machine.kubelet.extraConfig.serverTLSBootstrap, false)
    fqdn = try(local.kube_node.registerWithFQDN, local.legacy.machine.kubelet.registerWithFQDN, false)
    capability_label = try(local.kube_node.labels["platform.io/hardware-capability.storage"], local.legacy.machine.nodeLabels["platform.io/hardware-capability.storage"], "") == "true"
    cilium = local.native ? !contains([for doc in local.validation_documents : try(doc.kind, "")], "KubeFlannelCNIConfig") : try(local.legacy.cluster.network.cni.name == "none", false)
    proxy = local.native ? (var.machine_type == "controlplane" ? try(local.proxy.enabled == false, false) : local.proxy == null) : try(local.legacy.cluster.proxy.disabled, false)
    scheduling = local.native ? (var.machine_type == "controlplane" ? (try(local.kube_node.taints["node-role.kubernetes.io/control-plane"], "") == "NoSchedule") == !var.allow_scheduling : true) : local.legacy.cluster.allowSchedulingOnControlPlanes == var.allow_scheduling
    controlplane_label = !local.native || var.machine_type != "controlplane" ? true : can(local.kube_node.labels["node-role.kubernetes.io/control-plane"])
    cert_approver = local.native ? contains([for doc in local.validation_documents : try(doc.name, "") if try(doc.kind, "") == "KubeInlineManifestConfig"], "kubelet-csr-approver") == (var.machine_type == "controlplane") : contains([for manifest in try(local.legacy.cluster.inlineManifests, []) : manifest.name], "kubelet-csr-approver") == (var.machine_type == "controlplane")
  }
}
output "validation_config" {
  value = data.talos_machine_configuration.probe.machine_configuration
  sensitive = true
}
EOF
tofu -chdir="${WORK}/render" init -input=false -no-color >"${WORK}/render-init.log" 2>&1 || { cat "${WORK}/render-init.log"; exit 2; }
cat >"${WORK}/validation_override.tf" <<'EOF'
locals {
  node_installer_images = { for name in keys(var.nodes) : name => "factory.talos.dev/metal-installer/fixture:v1.14.2" }
}
resource "terraform_data" "argocd_render" {
  input = "apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: argocd-seed-fixture\n  namespace: argocd\n"
}
resource "terraform_data" "cilium_render" {
  input = "apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: cilium-seed-fixture\n  namespace: kube-system\n"
}
EOF
cp -R "${ROOT}/tofu/modules/talos-cluster/helm" "${ROOT}/tofu/modules/talos-cluster/manifests" "${WORK}/"
tofu -chdir="${WORK}" init -input=false -no-color >"${WORK}/init.log" 2>&1 || { cat "${WORK}/init.log"; exit 2; }
for schema in v1.13.10 v1.14.2; do
  kubernetes=v1.36.4
  if [[ "${schema}" == v1.14.2 ]]; then kubernetes=v1.37.1; fi
  for scheduling in false true; do
    cat >"${WORK}/probe.auto.tfvars" <<EOF
cluster_name = "validation"
cluster_endpoint = "https://192.0.2.1:6443"
talos_version = "${schema}"
kubernetes_version = "${kubernetes}"
deploy_argocd = true
sops_age_key = "AGE-SECRET-KEY-1TEST-FIXTURE-NOT-A-REAL-KEY"
allow_scheduling_on_controlplanes = ${scheduling}
register_with_fqdn = true
images = { intel = { architecture = "amd64", cpu_vendor = "intel", extensions = [] } }
hardware_capabilities = { storage = { requires_features = ["drbd-kernel-module"], provisioning_profiles = ["drbd"], emits_label = "platform.io/hardware-capability.storage" } }
nodes = {
  cp = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = ["storage"] }
  worker = { ip = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = ["storage"] }
}
EOF
    if [[ "${schema}" == v1.14.2 ]]; then
      cat >>"${WORK}/probe.auto.tfvars" <<'EOF'
config_patches = ["apiVersion: v1alpha1\nkind: UnattendedInstallConfig\nprovisioning:\n  diskSelector:\n    match: disk.dev_path == \"/dev/vda\"\n"]
EOF
    fi
    tofu -chdir="${WORK}" apply -target=data.talos_machine_configuration.controlplane -target=data.talos_machine_configuration.worker \
      -auto-approve -input=false -no-color >"${WORK}/seeds.log" 2>&1 || {
        echo "Local seed fixture setup failed" >&2; exit 1;
      }
    printf '%s\n' 'nonsensitive(jsonencode({controlplane=local.controlplane_machine_config_patches,worker=local.worker_machine_config_patches,nodes=local.node_config_patches}))' |
      tofu -chdir="${WORK}" console >"${WORK}/patches.json"
    for role in controlplane worker; do
      python3 - "${WORK}" "${schema}" "${role}" "${scheduling}" "${kubernetes}" <<'PYCODE'
import json, pathlib, sys
root, schema, role = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
patches = json.loads(json.loads((root / "patches.json").read_text()))
(root / "render/validation.auto.tfvars.json").write_text(json.dumps({
    "talos_version": schema, "kubernetes_version": sys.argv[5], "machine_type": role,
    "allow_scheduling": sys.argv[4] == "true",
    "config_patches": patches[role] + patches["nodes"]["cp" if role == "controlplane" else "worker"]}))
PYCODE
      tofu -chdir="${WORK}/render" apply -auto-approve -input=false -no-color >"${WORK}/render.log" 2>&1 || {
        echo "Provider render failed for ${schema}/${role}; no config or PKI printed." >&2; exit 1;
      }
      tofu -chdir="${WORK}/render" output -raw validation_config >"${WORK}/${role}-patched.yaml"
      talosctl validate --config "${WORK}/${role}-patched.yaml" --mode metal
      tofu -chdir="${WORK}/render" output -json validation_checks >"${WORK}/checks.json"
      python3 - "${WORK}/checks.json" <<'PYCODE'
import json, sys
checks = json.load(open(sys.argv[1]))
failed = [name for name, passed in checks.items() if passed is not True]
if failed:
    sys.exit("Rendered configuration assertions failed: " + ", ".join(failed))
PYCODE
    done
    echo "PASS: ${schema}, scheduling=${scheduling}, both roles, Cilium, ArgoCD seeds, FQDN, DRBD and cert-approver"
  done
done
