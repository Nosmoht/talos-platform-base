# DietPi to Talos Migration Plan (Pi Edge Node)

## Scope

- Replace the current Raspberry Pi host (`192.168.2.200`, DietPi) with a Talos worker node.
- New static node IP: `192.168.2.68`.
- Keep edge ingress/Gateway fully Kubernetes-managed (GitOps), no host cert sync.
- Use USB boot media prepared out-of-band.

## Why This Migration

- Removes host-managed edge stack drift (`nginx`, nftables, cert-sync timers).
- Certificates remain in-cluster (`cert-manager` + Gateway TLS secret refs).
- Source-IP/header behavior stays inside cluster config and can be versioned in Git.

## Branch Artifacts

This branch adds the Pi-specific Talos assets:

- `talos/talos-factory-schematic-pi.yaml`
- `talos/nodes/node-pi-01.yaml`
- `talos/patches/worker-pi.yaml`
- `talos/Makefile` updates for `node-pi-01`, `PI_SCHEMATIC_ID`, `PI_INSTALL_IMAGE`
- `.schematic-ids.mk` now includes `PI_SCHEMATIC_ID`

## Pre-Migration Checklist (Do Not Skip)

1. Export current Pi state (for rollback):
   - `/etc/nginx/`
   - `/etc/nftables.conf`
   - `/etc/systemd/system/homelab-nginx-cert-sync.*`
2. Keep existing DietPi boot disk intact.
   - Boot Talos from separate USB only.
3. Confirm API reachability from new node subnet:
   - control-plane endpoint `https://192.168.2.60:6443`
4. Reserve Pi hostname and static IP in inventory:
   - `node-pi-01` -> `192.168.2.68`
5. Record Pi NIC MAC and target USB disk ID from Talos installer shell.

## Required Manual Edits Before Apply

Update `talos/nodes/node-pi-01.yaml`:

- `machine.install.disk` -> real persistent by-id path for the USB boot disk.
- `machine.network.interfaces[0].deviceSelector.hardwareAddr` -> real Pi Ethernet MAC.

## Migration Phases

### Phase 1: Build and Validate Config (No Traffic Cutover Yet)

1. Regenerate schematics:
   - `make -C talos schematics`
2. Generate machine configs:
   - `make -C talos gen-configs`
3. Validate generated Pi worker config exists:
   - `talos/generated/worker/node-pi-01.yaml`

### Phase 2: Bring Pi into Cluster as Talos Worker

1. Boot Pi from Talos USB installer.
2. Apply initial config (insecure bootstrap path):
   - `make -C talos install-node-pi-01`
3. Verify node joins:
   - `kubectl get nodes -o wide | grep node-pi-01`
4. Verify Cilium/Envoy scheduling health on the new node:
   - `kubectl -n kube-system get pods -o wide | grep node-pi-01`

At this point, traffic can still flow through the existing DietPi edge path.

### Phase 3: Shift Edge to Cluster-Only

1. Change router/FritzBox WAN forward target:
   - from `192.168.2.200:443` to Gateway VIP `192.168.2.70:443`
2. Validate public services over Gateway:
   - Grafana/ArgoCD/Dex hostnames.
3. Remove host-edge dependency:
   - stop using host nginx and host cert sync mechanism.
4. Remove temporary Pi host NAT/proxy assumptions from operational docs.

### Phase 4: Decommission DietPi Host Role

1. Keep DietPi disk as rollback image for one maintenance window.
2. After stable period, remove obsolete host services/config from runbooks:
   - `/etc/nginx/sites-available/homelab-gateway-proxy`
   - `/etc/systemd/system/homelab-nginx-cert-sync.*`
   - host-specific nftables edge forwarding rules.

## Rollback Plan

### Rollback A: Pi Talos fails to join

- Reboot back to DietPi disk.
- Keep router forwarding to `192.168.2.200`.
- Cluster remains unchanged.

### Rollback B: Pi joins, but ingress cutover fails

- Revert router forwarding back to `192.168.2.200`.
- Keep Pi as non-critical Talos worker for debugging.

### Rollback C: Post-cutover instability

- Re-enable DietPi edge path (boot old disk, restore saved `/etc/nginx` and nftables).
- Repoint router to `192.168.2.200`.

## Risk Notes

- Do not repurpose `192.168.2.200` and switch ingress in the same step.
- Do not overwrite DietPi disk until at least one stable maintenance window passes.
- Keep control-plane and Cilium health checks green before and after router changes.

## Recommended Execution Window

- Run in a maintenance window with console access to the Pi and router admin access.
- Announce a brief ingress interruption window for the router target flip.
