#!/usr/bin/env bash
# translate-legacy-cluster-yaml.sh — Convert legacy homelab cluster.yaml (OLD shape)
# to the 5-axis format used by Makefile.lib / talos/schemas/cluster.schema.json.
#
# Usage:
#   translate-legacy-cluster-yaml.sh <input-cluster.yaml> [output-file]
#
# If output-file is omitted, writes to stdout.
# If output-file is "-", writes to stdout.
#
# Hard-coded defaults (documented for transparency):
#   - All nodes get infrastructure-platform: metal  (homelab is bare-metal)
#   - arch: arm64 for nodes whose name matches node-pi-*; amd64 for all others
#   - hardware-platform: raspberry-pi-4 for arm64 nodes; intel-generic for all
#     amd64 nodes (a GPU server is still an x86-64 platform — GPU presence is
#     captured on Axis 5 via the gpu-nvidia hardware-capability, not Axis 4)
#   - GPU nodes (name matches node-gpu-*) get role: gpu-worker and
#       hardware_capabilities: [gpu-nvidia] matching the legacy GPU worker
#       patch set (gvisor lives in roles.gpu-worker.patches[], not as a cap)
#   - Pi nodes (name matches node-pi-*) get role: worker and hardware_capabilities:
#       [pi-worker] matching the legacy Pi worker patch set
#   - Control-plane nodes get role: controlplane and hardware_capabilities: [drbd-storage]
#   - Standard workers get role: worker and hardware_capabilities:
#       [drbd-storage, kubevirt-networking] (gvisor is workload-runtime-class,
#       carried by roles.worker.patches[] — see talos/AGENTS.md §Patch slots)
#
# Mapping from legacy nodes/* fields to 5-axis cluster.yaml:
#   nodes.control_plane[]  → role=controlplane, arch=amd64, infra=metal
#   nodes.workers[]        → role=worker, arch=amd64, infra=metal
#   nodes.gpu_workers[]    → role=gpu-worker, arch=amd64, infra=metal, hw=intel-generic, caps=[gpu-nvidia]
#   nodes.pi_nodes[]       → role=pi-worker,  arch=arm64, infra=metal, hw=raspberry-pi-4, caps=[pi-worker]
#   nodes[].nic            → nic field (carried through for per-node reference)
#
# Workload-runtime-class concerns (gvisor sandbox) are NOT modeled on Axis 5;
# the worker-gvisor.yaml patch lives in roles.worker.patches[] /
# roles.gpu-worker.patches[] per talos/AGENTS.md §"Patch slots — where things
# go" and docs/adr-three-layer-capability-architecture.md §"Workload-class
# out-of-scope".
#
# The roles[].patches arrays in the translated output match the legacy Makefile
# patch order exactly (required for bit-identity verification in Phase 1C-3):
#
#   controlplane: patches/common.yaml, patches/drbd.yaml, patches/controlplane.yaml
#   worker (standard): patches/common.yaml, patches/worker-gvisor.yaml,
#                      patches/drbd.yaml, patches/worker-kubevirt.yaml
#   worker (gpu):     patches/common.yaml, patches/worker-gvisor.yaml, patches/worker-gpu.yaml
#   worker (pi):      patches/common.yaml, patches/worker-pi.yaml, patches/pi-firewall.yaml
#
# The translated cluster.yaml does NOT render NTP config (the legacy _out/<overlay>/cluster.yaml
# step); that is a consumer-side responsibility in Phase 3 cut-over.
#
# Schema version: 5-axis v1 (matches talos/schemas/cluster.schema.json as of Phase 1B)
#
# Dependencies: yq (mikefarah v4+), bash 3.2+

set -euo pipefail

INPUT="${1:?Usage: $0 <input-cluster.yaml> [output-file]}"
OUTPUT="${2:--}"   # default: stdout

if [[ ! -f "$INPUT" ]]; then
    echo "ERROR: input file not found: $INPUT" >&2
    exit 1
fi

# Read legacy fields
CLUSTER_NAME=$(yq -r '.cluster.name' "$INPUT")
API_VIP=$(yq -r '.cluster.api_vip' "$INPUT")
# Legacy gateway_vip is intentionally dropped: in v0.6+ cluster identity holds
# only the single Kubernetes API VIP. Gateway/LoadBalancer VIPs belong with
# the consumer's Gateway-API manifests (a cluster may host multiple Gateways).
NETWORK=$(yq -r '.cluster.network // ""' "$INPUT")
GATEWAY=$(yq -r '.cluster.gateway // ""' "$INPUT")
# Legacy schema only carried a single NTP server; map to a single-element
# ntp_servers list in the v0.6.0 output. Consumers should expand to ≥2
# servers post-translation for redundancy.
NTP_SERVER=$(yq -r '.cluster.ntp_server // ""' "$INPUT")
OVERLAY=$(yq -r '.cluster.overlay // .cluster.name' "$INPUT")
TARGET_REVISION=$(yq -r '.cluster.target_revision // "main"' "$INPUT")
REPO_URL=$(yq -r '.repo.url // ""' "$INPUT")

# Build nodes YAML fragment
NODES_YAML=""

# Helper: emit one node entry
emit_node() {
    local name="$1"
    local ip="$2"
    local role="$3"
    local arch="$4"
    local hw_platform="$5"
    local caps="$6"   # yaml list as a string, already indented
    local nic="$7"

    NODES_YAML+="  - name: $name
    role: $role
    arch: $arch
    infrastructure-platform: metal
    hardware-platform: $hw_platform
    hardware_capabilities:
$caps
    ip: $ip
"
    if [[ -n "$nic" && "$nic" != "null" ]]; then
        NODES_YAML+="    nic: $nic
"
    fi
}

# Control-plane nodes
CP_COUNT=$(yq -r '.nodes.control_plane | length' "$INPUT" 2>/dev/null || echo 0)
IDX=0
while [[ $IDX -lt $CP_COUNT ]]; do
    NAME=$(yq -r ".nodes.control_plane[$IDX].name" "$INPUT")
    IP=$(yq -r ".nodes.control_plane[$IDX].ip" "$INPUT")
    NIC=$(yq -r ".nodes.control_plane[$IDX].nic // \"\"" "$INPUT")
    emit_node "$NAME" "$IP" "controlplane" "amd64" "intel-generic" \
        "      - drbd-storage" "$NIC"
    IDX=$(( IDX + 1 ))
done

# Standard workers
W_COUNT=$(yq -r '.nodes.workers | length' "$INPUT" 2>/dev/null || echo 0)
IDX=0
while [[ $IDX -lt $W_COUNT ]]; do
    NAME=$(yq -r ".nodes.workers[$IDX].name" "$INPUT")
    IP=$(yq -r ".nodes.workers[$IDX].ip" "$INPUT")
    NIC=$(yq -r ".nodes.workers[$IDX].nic // \"\"" "$INPUT")
    emit_node "$NAME" "$IP" "worker" "amd64" "intel-generic" \
        "      - drbd-storage
      - kubevirt-networking" "$NIC"
    IDX=$(( IDX + 1 ))
done

# GPU workers
GPU_COUNT=$(yq -r '.nodes.gpu_workers | length' "$INPUT" 2>/dev/null || echo 0)
IDX=0
while [[ $IDX -lt $GPU_COUNT ]]; do
    NAME=$(yq -r ".nodes.gpu_workers[$IDX].name" "$INPUT")
    IP=$(yq -r ".nodes.gpu_workers[$IDX].ip" "$INPUT")
    NIC=$(yq -r ".nodes.gpu_workers[$IDX].nic // \"\"" "$INPUT")
    emit_node "$NAME" "$IP" "gpu-worker" "amd64" "intel-generic" \
        "      - gpu-nvidia" "$NIC"
    IDX=$(( IDX + 1 ))
done

# Pi nodes
PI_COUNT=$(yq -r '.nodes.pi_nodes | length' "$INPUT" 2>/dev/null || echo 0)
IDX=0
while [[ $IDX -lt $PI_COUNT ]]; do
    NAME=$(yq -r ".nodes.pi_nodes[$IDX].name" "$INPUT")
    IP=$(yq -r ".nodes.pi_nodes[$IDX].ip" "$INPUT")
    NIC=$(yq -r ".nodes.pi_nodes[$IDX].nic // \"\"" "$INPUT")
    emit_node "$NAME" "$IP" "pi-worker" "arm64" "raspberry-pi-4" \
        "      - pi-worker" "$NIC"
    IDX=$(( IDX + 1 ))
done

# Compose the output
TRANSLATED=$(cat <<YAML
# Translated from legacy homelab cluster.yaml by translate-legacy-cluster-yaml.sh.
# Source: $(realpath "$INPUT")
# This file is INFORMATIONAL — do not commit to the homelab repo.
# Use as ENV= input to Makefile.lib targets (bit-identity verification in Phase 1C-3).
#
# Hard-coded defaults applied:
#   - infrastructure-platform: metal (all nodes)
#   - arch: amd64 (except node-pi-* → arm64)
#   - hardware-platform: intel-generic (x86-64; GPU nodes included) /
#                        raspberry-pi-4 (arm64)
#   - roles[].patches match legacy Makefile patch order for bit-identity parity

cluster:
  name: $CLUSTER_NAME
  overlay: $OVERLAY
  vip: $API_VIP
  network: $NETWORK
  gateway: $GATEWAY
  ntp_servers:
    - $NTP_SERVER
  target_revision: $TARGET_REVISION

roles:
  controlplane:
    description: "Kubernetes control-plane node"
    patches:
      - patches/common.yaml
      - patches/drbd.yaml
      - patches/controlplane.yaml

  worker:
    description: "Standard Kubernetes worker (kubevirt-eligible)"
    patches:
      - patches/common.yaml
      - patches/worker-gvisor.yaml
      - patches/drbd.yaml
      - patches/worker-kubevirt.yaml

  gpu-worker:
    description: "GPU Kubernetes worker"
    patches:
      - patches/common.yaml
      - patches/worker-gvisor.yaml
      - patches/worker-gpu.yaml

  pi-worker:
    description: "Raspberry Pi Kubernetes worker"
    patches:
      - patches/common.yaml
      - patches/worker-pi.yaml
      - patches/pi-firewall.yaml

architectures:
  amd64:
    talos-arch: amd64
    compatible-infrastructure-platforms:
      - metal
  arm64:
    talos-arch: arm64
    compatible-infrastructure-platforms:
      - metal

infrastructure-platforms:
  metal:
    installer-profile: metal
    install-image-template: "factory.talos.dev/metal-installer/\${SCHEMATIC_ID}:\${TALOS_VERSION}"

hardware-platforms:
  intel-generic:
    vendor: Intel
    model: "Generic x86-64 (includes servers carrying PCIe GPUs)"
  raspberry-pi-4:
    vendor: "Raspberry Pi Foundation"
    model: "Raspberry Pi 4 Model B"

hardware-capabilities:
  drbd-storage:
    description: "DRBD distributed block storage (applied to all standard nodes)"
    patches:
      - file: patches/drbd.yaml

  kubevirt-networking:
    description: "KubeVirt VM networking via VLAN + Linux bridge"
    placeholder_bindings:
      NIC_NAME: machine.network.bridge.nic
    patches:
      - file: patches/worker-kubevirt.yaml

  gpu-nvidia:
    description: "NVIDIA GPU passthrough"
    patches:
      - file: patches/worker-gpu.yaml

  pi-worker:
    description: "Raspberry Pi worker (ARM64, USB boot)"
    patches:
      - file: patches/worker-pi.yaml
      - file: patches/pi-firewall.yaml

nodes:
$NODES_YAML
repo:
  url: $REPO_URL
YAML
)

if [[ "$OUTPUT" == "-" ]]; then
    printf '%s\n' "$TRANSLATED"
else
    printf '%s\n' "$TRANSLATED" > "$OUTPUT"
    echo "Translated cluster.yaml written to: $OUTPUT" >&2
fi
