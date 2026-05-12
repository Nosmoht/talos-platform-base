#!/usr/bin/env bash
# render-capability-reference.sh — regenerate docs/capability-reference.md
# from the PNI capability registry ConfigMap.
#
# Deterministic, idempotent. CI runs this with --check and fails if the
# generated file is stale (regen diff ≠ 0).
#
# Usage:
#   scripts/render-capability-reference.sh           # write docs/capability-reference.md
#   scripts/render-capability-reference.sh --check   # verify file is up-to-date, exit 1 if not
#   scripts/render-capability-reference.sh --stdout  # write to stdout, do not touch file
#
# Dependencies: yq (mikefarah, v4+), bash 4+.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY_FILE="$REPO_ROOT/kubernetes/base/infrastructure/platform-network-interface/resources/capability-registry-configmap.yaml"
OUTPUT_FILE="$REPO_ROOT/docs/capability-reference.md"

mode="write"
case "${1:-}" in
  --check) mode="check" ;;
  --stdout) mode="stdout" ;;
  --help|-h)
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  "") ;;
  *) echo "unknown flag: $1" >&2; exit 2 ;;
esac

command -v yq >/dev/null 2>&1 || { echo "ERROR: yq not found in PATH" >&2; exit 2; }

# Extract the inlined YAML payload (.data."capabilities.yaml") and reparse it.
caps_yaml="$(yq -r '.data."capabilities.yaml"' "$REGISTRY_FILE")"
iface_version="$(yq -r '.data.interfaceVersion' "$REGISTRY_FILE")"

render() {
  cat <<EOF
<!--
GENERATED FILE — DO NOT EDIT BY HAND.
Source of truth: kubernetes/base/infrastructure/platform-network-interface/resources/capability-registry-configmap.yaml
Regenerate: scripts/render-capability-reference.sh
-->

# PNI Capability Reference

**Interface version:** \`$iface_version\`

This document is generated from the PNI capability registry ConfigMap.
Each entry below corresponds to one capability identifier usable as the
suffix of \`platform.io/consume.<id>\` and
\`platform.io/capability-consumer.<id>\` labels in consumer manifests.

For the contract semantics (producer/consumer symmetry, per-instance
scoping, alias mechanism, denial messages), see
[ADR: Capability Producer/Consumer Symmetry](./adr-capability-producer-consumer-symmetry.md).

---

## Summary table

| ID | Stability | Instanced | Status |
|---|---|---|---|
EOF

  # Emit summary row per capability. yq's mikefarah dialect rejects inline
  # if/then/else in this context, so we stream TSV and format with bash.
  while IFS=$'\t' read -r row_id row_stab row_inst row_dep row_int row_sunset; do
    [ -z "$row_id" ] && continue
    row_status="active"
    [ "$row_int" = "true" ] && row_status="internal"
    if [ "$row_dep" = "true" ]; then
      row_status="deprecated → sunset ${row_sunset:-—}"
    fi
    row_inst_label="no"
    [ "$row_inst" = "true" ] && row_inst_label="yes"
    printf "| \`%s\` | %s | %s | %s |\n" "$row_id" "${row_stab:-—}" "$row_inst_label" "$row_status"
  done < <(echo "$caps_yaml" | yq -r '.capabilities[] | [.id, (.stability // "—"), (.instanced // false), (.deprecated // false), (.internal // false), (.sunset // "")] | @tsv')

  echo ""
  echo "---"
  echo ""
  echo "## Capabilities"
  echo ""

  # One section per capability, in registry order.
  local count
  count="$(echo "$caps_yaml" | yq -r '.capabilities | length')"
  for i in $(seq 0 $((count - 1))); do
    local id stab inst dep sunset replaced split desc impls instsrc
    id="$(echo "$caps_yaml" | yq -r ".capabilities[$i].id")"
    stab="$(echo "$caps_yaml" | yq -r ".capabilities[$i].stability // \"—\"")"
    inst="$(echo "$caps_yaml" | yq -r ".capabilities[$i].instanced // false")"
    dep="$(echo "$caps_yaml" | yq -r ".capabilities[$i].deprecated // false")"
    sunset="$(echo "$caps_yaml" | yq -r ".capabilities[$i].sunset // \"\"")"
    replaced="$(echo "$caps_yaml" | yq -r ".capabilities[$i].replaced_by // \"\"")"
    split="$(echo "$caps_yaml" | yq -r ".capabilities[$i].split_into // [] | join(\", \")")"
    desc="$(echo "$caps_yaml" | yq -r ".capabilities[$i].description // \"\"")"
    # instance_source can be a scalar (e.g. "kv-mount") or a {apiVersion, kind} map.
    # yq inline if/then/else is unreliable here; resolve in two passes.
    instsrc_raw="$(echo "$caps_yaml" | yq -r ".capabilities[$i].instance_source // \"\"")"
    if [ "$instsrc_raw" = "" ] || [ "$instsrc_raw" = "null" ]; then
      instsrc=""
    elif echo "$instsrc_raw" | grep -q '^apiVersion:'; then
      instsrc="$(echo "$caps_yaml" | yq -r ".capabilities[$i].instance_source.apiVersion + \"/\" + .capabilities[$i].instance_source.kind")"
    else
      instsrc="$instsrc_raw"
    fi

    echo "### \`$id\`"
    echo ""
    echo "- **Stability:** $stab"
    [ "$inst" = "true" ] && echo "- **Instanced:** yes — instance source: \`$instsrc\`"
    [ "$dep" = "true" ] && {
      echo "- **Deprecated** — sunset: \`$sunset\`"
      [ -n "$replaced" ] && echo "- **Replaced by:** \`$replaced\`"
      [ -n "$split" ] && echo "- **Split into:** \`$split\`"
    }

    # Stream TSV per implementation, format in bash.
    impls=""
    while IFS=$'\t' read -r impl_tool impl_port impl_proto; do
      [ -z "$impl_tool" ] && continue
      if [ -n "$impl_port" ] && [ "$impl_port" != "null" ]; then
        impls+="  - \`$impl_tool\` (port \`$impl_port\`, protocol \`$impl_proto\`)"$'\n'
      else
        impls+="  - \`$impl_tool\`"$'\n'
      fi
    done < <(echo "$caps_yaml" | yq -r ".capabilities[$i].implementations // [] | .[] | [.tool, (.endpoint.port // \"\"), (.endpoint.protocol // \"\")] | @tsv")
    if [ -n "$impls" ]; then
      echo "- **Implementations:**"
      echo "$impls"
    fi

    if [ -n "$desc" ] && [ "$desc" != "null" ]; then
      echo ""
      echo "$desc"
    fi

    # Disambiguation block for splits.
    local disamb
    disamb="$(echo "$caps_yaml" | yq -r ".capabilities[$i].disambiguation // \"\"")"
    if [ -n "$disamb" ] && [ "$disamb" != "null" ]; then
      echo ""
      echo "**Disambiguation:** $disamb"
    fi

    # Consumer label examples.
    echo ""
    echo "**Consumer labels:**"
    echo ""
    if [ "$inst" = "true" ]; then
      echo "\`\`\`yaml"
      echo "# Namespace"
      echo "metadata:"
      echo "  labels:"
      echo "    platform.io/consume.$id.<instance>: \"true\""
      echo "# Pod template"
      echo "metadata:"
      echo "  labels:"
      echo "    platform.io/capability-consumer.$id.<instance>: \"true\""
      echo "\`\`\`"
    elif [ "$dep" = "true" ]; then
      echo ""
      echo "_Deprecated — do not introduce in new manifests._"
    else
      echo "\`\`\`yaml"
      echo "# Namespace"
      echo "metadata:"
      echo "  labels:"
      echo "    platform.io/consume.$id: \"true\""
      echo "# Pod template"
      echo "metadata:"
      echo "  labels:"
      echo "    platform.io/capability-consumer.$id: \"true\""
      echo "\`\`\`"
    fi
    echo ""
  done
}

case "$mode" in
  stdout)
    render
    ;;
  write)
    render > "$OUTPUT_FILE"
    echo "wrote $OUTPUT_FILE"
    ;;
  check)
    tmpfile="$(mktemp)"
    trap 'rm -f "$tmpfile"' EXIT
    render > "$tmpfile"
    if ! diff -u "$OUTPUT_FILE" "$tmpfile" >&2; then
      echo "ERROR: $OUTPUT_FILE is out of date. Run scripts/render-capability-reference.sh" >&2
      exit 1
    fi
    echo "OK: $OUTPUT_FILE is up-to-date"
    ;;
esac
