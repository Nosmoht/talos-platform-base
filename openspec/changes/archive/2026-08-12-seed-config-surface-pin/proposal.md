## Why

The Cilium seed bypasses the kustomize/conftest render gate, and nothing pinned a
single key of its rendered `cilium-config`. A chart bump could therefore move a
datapath- or security-relevant default straight into the create-only controlplane
machine configuration with no gate failing.

This is not hypothetical. The Cilium 1.19.4 → 1.20.0 bump flipped
`bpf-lb-algorithm-annotation` from `"false"` to `"true"` — the chart forces it on
whenever `gatewayAPI.enabled`, which is the base default — and that turns a
previously inert `service.cilium.io/lb-algorithm` Service annotation live. It was
found by a hand-run render diff, not by the test suite. ADR-0022 recorded the gap:
"no assert pinning any of the keys above — so the next bump can flip one silently."

## What Changes

- A `composition.tftest.hcl` run compares the seed's full `cilium-config` KEY SET
  against `tests/fixtures/cilium-config-keys.txt`, so any added or removed key
  fails until the fixture is refreshed deliberately.
- The same run pins the VALUES of a curated set: `bpf-lb-algorithm-annotation`,
  `kube-proxy-replacement`, `enable-host-firewall`, `enable-datapath-plugins`,
  `gateway-api-use-remote-address`.

Both layers are needed. The key set alone would NOT have caught the 1.20
regression, because the key exists in both charts and only its value moved; the
value pins alone would not catch a key appearing or disappearing.

## Capabilities

- `cilium-cni-delivery` — ADDED: a requirement that the seed's rendered config
  surface is pinned at key-set and curated-value level, with refresh framed as a
  deliberate act that answers the consumer-facing question in `UPGRADING.md`.

## Impact

No runtime change. A future chart bump now fails the module's test target until the
fixture is refreshed and the curated pins are re-confirmed — which is the point.

The curated set is explicitly open-ended rather than claimed exhaustive: it covers
the keys whose flip breaks the cluster silently or widens exposure, and grows as
bumps reveal more. Note the target carrying this run, `task tofu:test`, is
advisory in CI by design (a chart-registry outage must not block every `tofu/**`
merge), so the gate binds the bump workflow rather than the merge button.
