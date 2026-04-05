# Backlog

Single source of truth for all planned work, known bugs, ideas, and operational debt.

**Format:** Items ordered by priority (top = highest). Status prefixes:
- `[x]` done — `[ ]` agreed (ready for work) — `[~]` proposed (needs approval) — `[!]` blocked (reason noted)

---

## Enterprise Network Redesign

Blueprint: `docs/enterprise-network-architecture-blueprint.md` Section 15

### Phase 1: Quick Wins (Software-Only) — COMPLETE

- [x] Enable Cilium WireGuard strict mode (590e9ff, 7243acd, 0d764db)
- [x] Enable Hubble dynamic flow export — dropped + DNS flows (5fc2399, f0de11a)
- [x] Transition Kyverno PNI policies to enforce mode (c0d0ff5)

Implementation log: `docs/implementation-log-phase1-network-blueprint.md`

### Phase 2: VLAN Separation (Switch + Talos Config) — NOT STARTED

- [!] Configure Netgear switch trunk ports (VLAN 10 + 20) — blocked: physical access required
- [ ] Add VLAN patches to Talos machine config (management + storage VLAN interfaces on all nodes)
- [ ] Configure LinstorNodeConnection for storage VLAN (DRBD replication isolated to VLAN 20)

### Phase 3: Observability Stack — NOT STARTED

- [ ] Deploy Tetragon (runtime security observability, <1% overhead DaemonSet)
- [ ] Add Grafana compliance dashboards (policy coverage, verdict visualization)
- [ ] Implement flow log retention pipeline (Fluentbit → MinIO with lifecycle policies)

### Phase 4: Advanced Security — NOT STARTED

- [ ] Add DNS-aware egress filtering (PNI capability `internet-egress-fqdn`, Cilium toFQDNs)
- [ ] Deploy kube-bench for CIS benchmark automation (continuous compliance checking)
- [ ] Kyverno auto-generate default-deny policies (automatic isolation for new namespaces)

### Phase 5: Financial Sector Compliance — NOT STARTED

- [ ] Document Vault secrets management architecture (PCI-DSS key management)
- [ ] Implement OIDC authentication for kubectl (MFA-enforced API access)
- [ ] Deploy Trivy/Grype image scanning (continuous vulnerability detection)
- [ ] Establish quarterly policy review cadence (DORA periodic review)
- [ ] Create formal pen testing runbook (DORA TLPT + PCI segmentation validation)
- [~] Implement CDE node taints if needed (dedicated node pool isolation)

## Bugs

## Ideas

- [~] Evaluate intra-provider PNI capability (e.g. `linstor-internal`) to consolidate piraeus-datastore CNPs

## Tech Debt

- [ ] Hubble flow export logs have no rotation config — monitor node disk pressure until Fluentbit pipeline ships logs off-node
