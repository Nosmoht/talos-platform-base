# Talos library v0.5.3 — role-spec field rename

## default_patches → patches (breaking schema rename, non-breaking runtime)

The `roles[<role>].default_patches` schema field is renamed to `patches`
to reconcile a v0.5.1/v0.5.2 schema-vs-runtime drift. Every other artifact
(`argv-print.sh`, `translate-legacy-cluster-yaml.sh`, the v0.5.2 release
notes, and the only known v0.5.2 consumer `talos-homelab-cluster`) already
uses `patches`; the schema was the outlier.

Consumer impact: zero migration required for any v0.5.2 consumer that
followed `RELEASE-NOTES-v0.5.2.md:92,100,262` and used `patches:`. New
consumers onboarding against v0.5.3 will simply find a consistent contract.

### Pre-bump consumer survey (mandatory before vendoring v0.5.3)

v0.5.3 tightens `additionalProperties: false` on `$defs.role-spec`. The
producer-side I1.a survey assumes the only role-level keys in use across
known consumers are `description`, `patches`, `default_extensions`.
**Before bumping the OCI tag to v0.5.3, every consumer MUST verify their
cluster.yaml carries no other role-level keys.**

Run against your `cluster.yaml`:

```bash
yq -r '.roles[] | keys[]' cluster.yaml | sort -u
```

Expected output:

```
default_extensions
description
patches
```

If any other key appears, file a follow-up PR against `talos-platform-base`
to declare that key in `$defs.role-spec.properties` BEFORE bumping the
tag. v0.5.3 will reject schema validation for any role-level key not in
the declared properties set.

### Migration command (mikefarah yq v4 required)

For any cluster.yaml that still carries the old schema name:

```bash
yq -i '(.roles[] | select(has("default_patches"))) |= (.patches = .default_patches | del(.default_patches))' cluster.yaml
```

This renames the key in-place while preserving value order. Verify with
mikefarah/yq v4 (`yq --version`); the Python-`yq` wrapper has different
syntax and is NOT supported by this command.
