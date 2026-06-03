# `talos-cluster` adoption proof harness

Reproducible proof scripts for the **already-running-cluster adoption** path
documented in [`UPGRADING.md` §Adopting an already-running cluster](../../../../UPGRADING.md#adopting-an-already-running-cluster-no-re-bootstrap).
They turn the runbook's manual step-5 gate into runnable checks.

These are **operator-run**, not part of `task ci` — they need `talosctl` and/or
a decrypted secrets bundle, which a hermetic CI job does not have. They are
generic templates: no cluster identity is hardcoded; point them at your root.

| Script | Proves | Needs a cluster? | Needs a secrets bundle? |
|---|---|---|---|
| `pki-reconcile-microtest.sh` | the `talos_version` reconcile on an imported `talos_machine_secrets` is an in-place update that **preserves the PKI bytes** (does not regenerate) | no | no (generates a throwaway one) |
| `run-adoption-proof.sh` | importing the two identity resources then `tofu plan` reports **`0 to destroy`** (no PKI roll, no re-bootstrap) | no (plan is `-refresh=false`) | yes (your decrypted bundle) |

## `pki-reconcile-microtest.sh`

Self-contained. Generates a throwaway `talosctl gen secrets` bundle, imports it
into a one-resource root (talos_version → provider default `v1.3`), pins a higher
version, applies (state-only, no cluster), and asserts the `machine_secrets`
hash is unchanged.

```bash
./pki-reconcile-microtest.sh              # default pin v1.9
PIN_VERSION=v1.10 ./pki-reconcile-microtest.sh
```

Exit `0` = PKI preserved (PASS); `2` = skipped (missing `talosctl`/`tofu`/`jq`);
non-zero = the reconcile regenerated PKI (the adoption runbook's safety claim
would not hold — investigate before adopting any real cluster).

> Reference run (provider `siderolabs/talos`, OpenTofu 1.12): import sets
> `talos_version=v1.3`; reconcile to a higher pin leaves the `machine_secrets`
> sha256 identical — PASS.

## `run-adoption-proof.sh`

The reproducible form of the runbook step-5 gate, for your own throwaway dry run.

**Safety:** it copies your root's `*.tf` / `*.tfvars` / `patches/` into a temp
dir and runs `tofu init -backend=false` there, so your real (remote/encrypted)
state backend is never initialised or written. All imports land in disposable
local state. The temp dir is removed on exit. The `--bundle` plaintext is yours
to manage (see the runbook's "Plaintext hygiene").

```bash
# decrypt your bundle to a temp file first (see the runbook), then:
./run-adoption-proof.sh \
  --root ../path/to/your/opentofu/root \
  --bundle /path/to/decrypted-bundle.yaml \
  --module-addr module.cluster \
  -- -var-file=proof.tfvars      # pass-through tofu args (vars your root needs)
```

Exit `0` = `0 to destroy` (PASS); non-zero = a destroy is planned (a
`talos_machine_secrets` destroy = PKI regen; a `talos_machine_bootstrap` destroy
= re-bootstrap) — do **not** apply.

Your root's input variables must resolve in the copy (pass a `-var-file` after
`--`, or rely on an auto-loaded `terraform.tfvars`). If your root configures
state encryption with a required passphrase var, export it before running.

## Consumers

Consumers that vendor this module (git source or OCI artifact) get this `test/`
dir alongside the module. See `talos-homelab-cluster`'s `tofu/Taskfile.yml`
`proof` task for a wired example.
