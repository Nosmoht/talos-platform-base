# Backlog

Single source of truth for all planned work, known bugs, ideas, and operational debt.

**Format:** Items ordered by priority (top = highest). Status prefixes:
- `[x]` done — `[ ]` agreed (ready for work) — `[~]` proposed (needs approval) — `[!]` blocked (reason noted)

---

## Enterprise Network Redesign

Blueprint: `docs/enterprise-network-architecture-blueprint.md`

### Phase 1: Quick Wins — COMPLETE

- [x] Hubble dynamic flow export — dropped + DNS flows (5fc2399, f0de11a)
- [x] WireGuard strict mode encryption (590e9ff, 7243acd, 0d764db)
- [x] Kyverno PNI policies audit → enforce (c0d0ff5)

Implementation log: `docs/implementation-log-phase1-network-blueprint.md`

### Phase 2: VLAN Separation — NOT STARTED

- [ ] Storage VLAN 20 for DRBD isolation (LinstorNodeConnection, StorageClass PrefNic)
- [ ] Management VLAN 10 for API server/etcd (kube-apiserver advertise-address, etcd peer URLs)
- [!] Switch 802.1q trunk port configuration — blocked: physical access required

### Phase 3: Runtime Security & DNS Filtering — NOT STARTED

- [ ] Tetragon deployment (process-level security observability)
- [ ] DNS-aware egress filtering (PNI capability `internet-egress-fqdn`, Cilium toFQDNs)

### Phase 4: Policy Automation — NOT STARTED

- [ ] Auto-generate default-deny CiliumNetworkPolicy on namespace PNI labeling (Kyverno generate policy)
- [!] Per-namespace audit mode — blocked: upstream cilium/cilium#40621

### Phase 5: Compliance & Retention — NOT STARTED

- [ ] Fluentbit log shipping pipeline (Hubble dropped.log/dns.log → MinIO)
- [ ] MinIO Object Lock (WORM) for compliance retention (PCI-DSS Req 10.7)
- [ ] Grafana compliance dashboards (network policy coverage, DNS audit, enforcement progress)

## Bugs

## Ideas

## Tech Debt

- [ ] Hubble flow export logs have no rotation config — monitor node disk pressure until Fluentbit pipeline ships logs off-node
