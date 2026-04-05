- plan-talos-upgrade:
  - what to do after plan was approved -> missing info to "/execute-talos-upgrade"
  - auto install of required tools likq jq, yq, sops is really great. but: they should be documented as requirements.
  - ssh-keyscan is also really great
- execute-talos-upgrade:
  - summary/overview before upgrade
  - upgrade log?
  - summary/overview after upgrade
  - summary diff between before and after upgrade
- what if talosctl and kubectl arent installed?
- Skill to upgrade K8s
- static IPAM Plugin für multus nicht installiert

## platform-reliability-reviewer — known invariant gaps (from Apr 2026 retrospective)

- Gate T: Talos-layer runtime facts (schematic drift, kernel module gaps, sysctl drift, hostNetwork port
  collisions with apid/trustd/kubelet). Requires granting reviewer `talosctl` access + new invariant row.
  Red-teamer's top pick for next defect class — nvidia-extension-check already exists because this has
  shipped before.
- NVIDIA device plugin vs NFD label drift: DaemonSet selector drifts from NFD labels → pods schedule but
  `nvidia.com/gpu` capacity = 0. Probe: `kubectl describe node | grep nvidia.com/gpu`.
- cert-manager Certificate vs Gateway listener hostnames: HTTPRoute/Certificate mismatch or missing
  ReferenceGrant. Static review cannot detect this.
- LINSTOR replicaCount vs NVMe NFD count: StorageClass `replicaCount: 2` but fewer than 2 nodes with
  `storage-nvme.present=true` → PVC pending. Probe: `kubectl get nodes -l feature.node.kubernetes.io/storage-nvme.present=true --no-headers | wc -l`.
- SOPS/ExternalSecret key-shape drift: ExternalSecret syncs cleanly but Secret lacks the key the
  Deployment's `secretKeyRef` expects (upstream Vault key renamed).
- Kyverno policy effectiveness: Enforce vs Audit mode, namespace label coverage — not detectable statically.
- Propagate invariant-table + require-probe-evidence hook pattern to gitops-operator, talos-sre, researcher.