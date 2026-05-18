#!/usr/bin/env bash
# render-capability-index.sh — regenerate docs/platform-capability-index.md
# from docs/platform-capability-index.yaml.
#
# Deterministic, idempotent. CI runs this with --check and fails if the
# generated file is stale (regen diff ≠ 0).
#
# Usage:
#   scripts/render-capability-index.sh           # write docs/platform-capability-index.md
#   scripts/render-capability-index.sh --check   # verify file is up-to-date, exit 1 if not
#   scripts/render-capability-index.sh --stdout  # write to stdout, do not touch file
#
# Dependencies: yq (mikefarah, v4+), bash 4+.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INDEX_FILE="$REPO_ROOT/docs/platform-capability-index.yaml"
OUTPUT_FILE="$REPO_ROOT/docs/platform-capability-index.md"

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
[ -f "$INDEX_FILE" ] || { echo "ERROR: index not found: $INDEX_FILE" >&2; exit 2; }

schema_version="$(yq -r '.schema_version' "$INDEX_FILE")"
base_version="$(yq -r '.base_version' "$INDEX_FILE")"
default_owner="$(yq -r '.default_owner' "$INDEX_FILE")"
count="$(yq -r '.capabilities | length' "$INDEX_FILE")"

render() {
  cat <<EOF
<!--
GENERATED FILE — DO NOT EDIT BY HAND.
Source of truth: docs/platform-capability-index.yaml
Regenerate: scripts/render-capability-index.sh
-->

# Platform Capability Index (Layer A)

**Schema version:** \`$schema_version\` · **Base version stamp:** \`$base_version\` · **Default owner:** \`$default_owner\`

This document is generated from \`docs/platform-capability-index.yaml\`.
It is the **Layer A** catalogue defined in
[ADR — Two-Layer Capability Architecture](./adr-two-layer-capability-architecture.md):
the tool-capability-index that names every functional capability this
base provides, its current implementations, and what swap classes
exist between alternatives. For the network-trust subset (Layer B,
Kyverno-consumed), see
[capability-reference.md](./capability-reference.md).

---

## Summary

| ID | Stability | Domain | Topology | Layer B id |
|---|---|---|---|---|
EOF

  for i in $(seq 0 $((count - 1))); do
    id="$(yq -r ".capabilities[$i].id" "$INDEX_FILE")"
    stab="$(yq -r ".capabilities[$i].stability" "$INDEX_FILE")"
    layer="$(yq -r ".capabilities[$i].domain.layer" "$INDEX_FILE")"
    cat_name="$(yq -r ".capabilities[$i].domain.category" "$INDEX_FILE")"
    topo="$(yq -r ".capabilities[$i].deployment_topology // \"—\"" "$INDEX_FILE")"
    pni="$(yq -r ".capabilities[$i].pni_capability_id // \"—\"" "$INDEX_FILE")"
    [ "$pni" = "null" ] && pni="—"
    printf "| [\`%s\`](#%s) | %s | %s / %s | %s | %s |\n" \
      "$id" "$id" "$stab" "$layer" "$cat_name" "$topo" "$pni"
  done

  echo ""
  echo "---"
  echo ""
  echo "## Capabilities"
  echo ""

  for i in $(seq 0 $((count - 1))); do
    id="$(yq -r ".capabilities[$i].id" "$INDEX_FILE")"
    name="$(yq -r ".capabilities[$i].name" "$INDEX_FILE")"
    stab="$(yq -r ".capabilities[$i].stability" "$INDEX_FILE")"
    layer="$(yq -r ".capabilities[$i].domain.layer" "$INDEX_FILE")"
    cat_name="$(yq -r ".capabilities[$i].domain.category" "$INDEX_FILE")"
    topo="$(yq -r ".capabilities[$i].deployment_topology // \"\"" "$INDEX_FILE")"
    desc="$(yq -r ".capabilities[$i].description // \"\"" "$INDEX_FILE")"
    contract="$(yq -r ".capabilities[$i].contract // \"\"" "$INDEX_FILE")"
    pni="$(yq -r ".capabilities[$i].pni_capability_id // \"\"" "$INDEX_FILE")"
    [ "$pni" = "null" ] && pni=""
    replaced="$(yq -r ".capabilities[$i].replaced_by // \"\"" "$INDEX_FILE")"
    sunset_date="$(yq -r ".capabilities[$i].sunset.date // \"\"" "$INDEX_FILE")"
    sunset_tag="$(yq -r ".capabilities[$i].sunset.tag // \"\"" "$INDEX_FILE")"

    echo "### \`$id\`"
    echo ""
    echo "**$name** · stability \`$stab\` · domain $layer / $cat_name${topo:+ · topology \`$topo\`}"
    echo ""
    [ -n "$desc" ] && [ "$desc" != "null" ] && { echo "$desc"; echo ""; }

    if [ -n "$contract" ] && [ "$contract" != "null" ]; then
      echo "**Contract:**"
      echo ""
      echo '```text'
      printf '%s\n' "$contract"
      echo '```'
      echo ""
    fi

    # Independence test summary.
    ait="$(yq -r ".capabilities[$i].independence_test.alt_impls_exist // \"—\"" "$INDEX_FILE")"
    cts="$(yq -r ".capabilities[$i].independence_test.contract_stable // \"—\"" "$INDEX_FILE")"
    ilc="$(yq -r ".capabilities[$i].independence_test.independent_lifecycle // \"—\"" "$INDEX_FILE")"
    echo "**Independence test:** alt-impls=$ait · contract-stable=$cts · independent-lifecycle=$ilc"
    echo ""

    # Implementations.
    impl_len="$(yq -r ".capabilities[$i].implementations // [] | length" "$INDEX_FILE")"
    if [ "$impl_len" -gt 0 ]; then
      echo "**Implementations:**"
      echo ""
      for j in $(seq 0 $((impl_len - 1))); do
        iname="$(yq -r ".capabilities[$i].implementations[$j].name" "$INDEX_FILE")"
        istatus="$(yq -r ".capabilities[$i].implementations[$j].status" "$INDEX_FILE")"
        iswap="$(yq -r ".capabilities[$i].implementations[$j].swap_class" "$INDEX_FILE")"
        iext="$(yq -r ".capabilities[$i].implementations[$j].source.external // false" "$INDEX_FILE")"
        comp_len="$(yq -r ".capabilities[$i].implementations[$j].composition // [] | length" "$INDEX_FILE")"
        comp_list=""
        if [ "$comp_len" -gt 0 ]; then
          comp_list="$(yq -r ".capabilities[$i].implementations[$j].composition | join(\", \")" "$INDEX_FILE")"
        fi
        ext_marker=""
        if [ "$iext" != "false" ] && [ "$iext" != "null" ] && [ -n "$iext" ]; then
          ext_marker=" · _external_"
        fi
        if [ -n "$comp_list" ]; then
          printf -- '- `%s` — status `%s`, swap-class `%s`%s — composition: %s\n' \
            "$iname" "$istatus" "$iswap" "$ext_marker" "$comp_list"
        else
          printf -- '- `%s` — status `%s`, swap-class `%s`%s\n' \
            "$iname" "$istatus" "$iswap" "$ext_marker"
        fi
      done
      echo ""
    fi

    # Deprecation / replacement markers.
    if [ "$stab" = "deprecated" ]; then
      echo "**Deprecated** — sunset \`$sunset_date\` (tag \`$sunset_tag\`)"
      [ -n "$replaced" ] && echo "**Replaced by:** \`$replaced\`"
      echo ""
    fi
    if [ -n "$pni" ]; then
      echo "**Layer B (PNI) counterpart:** \`$pni\`"
      echo ""
    fi
  done
}

# Squash runs of blank lines down to one and ensure exactly one trailing
# newline so markdownlint's MD012 (no-multiple-blanks) stays clean.
# Bash $(...) already strips trailing newlines from the captured value;
# printf '%s\n' re-adds exactly one.
render_clean() {
  local out
  out="$(render | awk 'NF { blank=0 } !NF { blank++ } NF || blank<=1')"
  printf '%s\n' "$out"
}

case "$mode" in
  stdout)
    render_clean
    ;;
  write)
    render_clean > "$OUTPUT_FILE"
    echo "wrote $OUTPUT_FILE"
    ;;
  check)
    tmpfile="$(mktemp)"
    trap 'rm -f "$tmpfile"' EXIT
    render_clean > "$tmpfile"
    if ! diff -u "$OUTPUT_FILE" "$tmpfile" >&2; then
      echo "ERROR: $OUTPUT_FILE is out of date. Run scripts/render-capability-index.sh" >&2
      exit 1
    fi
    echo "OK: $OUTPUT_FILE is up-to-date"
    ;;
esac
