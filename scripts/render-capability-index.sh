#!/usr/bin/env bash
# render-capability-index.sh — regenerate the two layer-MD files from their
# YAML sources of truth:
#   - Layer A: docs/platform-capability-index.yaml      → docs/platform-capability-index.md
#   - Layer C: docs/platform-hardware-features.yaml     → docs/platform-hardware-features.md
#
# Deterministic, idempotent. CI runs this with --check and fails if any
# generated file is stale (regen diff ≠ 0). Layer B (PNI registry) is a
# Kyverno-consumed ConfigMap and has its own renderer
# (`scripts/render-capability-reference.sh`).
#
# Usage:
#   scripts/render-capability-index.sh                 # write both .md files
#   scripts/render-capability-index.sh --check         # verify both .md files up-to-date, exit 1 if not
#   scripts/render-capability-index.sh --stdout        # write Layer A .md to stdout, do not touch files
#   scripts/render-capability-index.sh --layer a       # only Layer A (write mode)
#   scripts/render-capability-index.sh --layer c       # only Layer C (write mode)
#   scripts/render-capability-index.sh --check --layer c   # only Layer C (check mode)
#
# Dependencies: yq (mikefarah, v4+), bash 4+.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INDEX_FILE="$REPO_ROOT/docs/platform-capability-index.yaml"
OUTPUT_FILE="$REPO_ROOT/docs/platform-capability-index.md"
HW_FEATURES_FILE="$REPO_ROOT/docs/platform-hardware-features.yaml"
HW_FEATURES_OUTPUT="$REPO_ROOT/docs/platform-hardware-features.md"

mode="write"
layer="all"
while [ $# -gt 0 ]; do
  case "$1" in
    --check) mode="check" ;;
    --stdout) mode="stdout" ;;
    --layer)
      shift
      case "${1:-}" in
        a|c|all) layer="$1" ;;
        *) echo "unknown --layer value: ${1:-<empty>} (expected a, c, or all)" >&2; exit 2 ;;
      esac
      ;;
    --help|-h)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    "") ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done

command -v yq >/dev/null 2>&1 || { echo "ERROR: yq not found in PATH" >&2; exit 2; }
[ -f "$INDEX_FILE" ] || { echo "ERROR: index not found: $INDEX_FILE" >&2; exit 2; }
[ -f "$HW_FEATURES_FILE" ] || { echo "ERROR: hardware-features registry not found: $HW_FEATURES_FILE" >&2; exit 2; }

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
[ADR — Three-Layer Capability Architecture](./adr-three-layer-capability-architecture.md)
(which supersedes the earlier
[Two-Layer ADR](./adr-two-layer-capability-architecture.md)):
the tool-capability-index that names every functional capability this
base provides, its current implementations, and what swap classes
exist between alternatives. For the network-trust subset (Layer B,
Kyverno-consumed), see
[capability-reference.md](./capability-reference.md). For the atomic
hardware-features registry (Layer C, referenced via
\`requires_hardware_features[]\`), see
[platform-hardware-features.md](./platform-hardware-features.md).

---

## Summary

| ID | Kind | Stability | Domain | Topology | Layer B id |
|---|---|---|---|---|---|
EOF

  for i in $(seq 0 $((count - 1))); do
    id="$(yq -r ".capabilities[$i].id" "$INDEX_FILE")"
    kind_val="$(yq -r ".capabilities[$i].kind // \"tool-capability\"" "$INDEX_FILE")"
    stab="$(yq -r ".capabilities[$i].stability" "$INDEX_FILE")"
    layer="$(yq -r ".capabilities[$i].domain.layer" "$INDEX_FILE")"
    cat_name="$(yq -r ".capabilities[$i].domain.category" "$INDEX_FILE")"
    topo="$(yq -r ".capabilities[$i].deployment_topology // \"—\"" "$INDEX_FILE")"
    pni="$(yq -r ".capabilities[$i].pni_capability_id // \"—\"" "$INDEX_FILE")"
    [ "$pni" = "null" ] && pni="—"
    printf "| [\`%s\`](#%s) | \`%s\` | %s | %s / %s | %s | %s |\n" \
      "$id" "$id" "$kind_val" "$stab" "$layer" "$cat_name" "$topo" "$pni"
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

    cap_kind="$(yq -r ".capabilities[$i].kind // \"tool-capability\"" "$INDEX_FILE")"
    echo "### \`$id\`"
    echo ""
    echo "**$name** · kind \`$cap_kind\` · stability \`$stab\` · domain $layer / $cat_name${topo:+ · topology \`$topo\`}"
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

render_hardware_features() {
  local hw_schema_version count
  hw_schema_version="$(yq -r '.schema_version' "$HW_FEATURES_FILE")"
  count="$(yq -r '.hardware_features | length' "$HW_FEATURES_FILE")"

  cat <<EOF
<!--
GENERATED FILE — DO NOT EDIT BY HAND.
Source of truth: docs/platform-hardware-features.yaml
Regenerate: scripts/render-capability-index.sh
-->

# Platform Hardware Features Registry (Layer C)

**Schema version:** \`$hw_schema_version\`

This document is generated from \`docs/platform-hardware-features.yaml\`.
It is the **Layer C** catalogue defined in
[ADR — Three-Layer Capability Architecture](./adr-three-layer-capability-architecture.md):
the static catalog of atomic hardware features that nodes in this
platform may carry. Layer A entries reference these via
\`requires_hardware_features[]\`; consumer-side \`cluster.yaml\` composite
capabilities reference them via \`requires_features[]\` under the
\`hardware-capabilities:\` block.

---

## Summary

| ID | Discovery Source | Node Label Key |
|---|---|---|
EOF

  local i id disc lbl
  for i in $(seq 0 $((count - 1))); do
    id="$(yq -r ".hardware_features[$i].id" "$HW_FEATURES_FILE")"
    disc="$(yq -r ".hardware_features[$i].discovery_source" "$HW_FEATURES_FILE")"
    lbl="$(yq -r ".hardware_features[$i].node_label_key // \"—\"" "$HW_FEATURES_FILE")"
    [ "$lbl" = "null" ] && lbl="—"
    printf "| [\`%s\`](#%s) | \`%s\` | \`%s\` |\n" "$id" "$id" "$disc" "$lbl"
  done

  echo ""
  echo "---"
  echo ""
  echo "## Features"
  echo ""

  local name desc disc lbl pred alt_len ref_len j alt ref
  for i in $(seq 0 $((count - 1))); do
    id="$(yq -r ".hardware_features[$i].id" "$HW_FEATURES_FILE")"
    name="$(yq -r ".hardware_features[$i].name" "$HW_FEATURES_FILE")"
    desc="$(yq -r ".hardware_features[$i].description" "$HW_FEATURES_FILE")"
    disc="$(yq -r ".hardware_features[$i].discovery_source" "$HW_FEATURES_FILE")"
    lbl="$(yq -r ".hardware_features[$i].node_label_key // \"\"" "$HW_FEATURES_FILE")"
    [ "$lbl" = "null" ] && lbl=""
    pred="$(yq -r ".hardware_features[$i].presence_predicate" "$HW_FEATURES_FILE")"

    echo "### \`$id\`"
    echo ""
    echo "**$name** · discovery-source \`$disc\`${lbl:+ · authoritative label \`$lbl\`}"
    echo ""
    printf '%s\n' "$desc"
    echo ""
    echo "**Presence predicate:**"
    echo ""
    printf '%s\n' "$pred"
    echo ""

    alt_len="$(yq -r ".hardware_features[$i].alt_label_keys // [] | length" "$HW_FEATURES_FILE")"
    if [ "$alt_len" -gt 0 ]; then
      echo "**Alternative label keys:**"
      echo ""
      for j in $(seq 0 $((alt_len - 1))); do
        alt="$(yq -r ".hardware_features[$i].alt_label_keys[$j]" "$HW_FEATURES_FILE")"
        printf -- '- `%s`\n' "$alt"
      done
      echo ""
    fi

    ref_len="$(yq -r ".hardware_features[$i].references // [] | length" "$HW_FEATURES_FILE")"
    if [ "$ref_len" -gt 0 ]; then
      echo "**References:**"
      echo ""
      for j in $(seq 0 $((ref_len - 1))); do
        ref="$(yq -r ".hardware_features[$i].references[$j]" "$HW_FEATURES_FILE")"
        printf -- '- <%s>\n' "$ref"
      done
      echo ""
    fi
  done
}

render_hw_clean() {
  local out
  out="$(render_hardware_features | awk 'NF { blank=0 } !NF { blank++ } NF || blank<=1')"
  printf '%s\n' "$out"
}

render_a_write() { render_clean > "$OUTPUT_FILE"; echo "wrote $OUTPUT_FILE"; }
render_c_write() { render_hw_clean > "$HW_FEATURES_OUTPUT"; echo "wrote $HW_FEATURES_OUTPUT"; }

check_one() {
  local label src tgt renderer
  label="$1"
  tgt="$2"
  renderer="$3"
  local tmpfile
  tmpfile="$(mktemp)"
  trap 'rm -f "$tmpfile"' RETURN
  "$renderer" > "$tmpfile"
  if ! diff -u "$tgt" "$tmpfile" >&2; then
    echo "ERROR: $tgt is out of date ($label). Run scripts/render-capability-index.sh" >&2
    return 1
  fi
  echo "OK: $tgt is up-to-date ($label)"
}

case "$mode" in
  stdout)
    render_clean
    ;;
  write)
    case "$layer" in
      a) render_a_write ;;
      c) render_c_write ;;
      all) render_a_write; render_c_write ;;
    esac
    ;;
  check)
    rc=0
    case "$layer" in
      a) check_one "Layer A" "$OUTPUT_FILE" render_clean || rc=1 ;;
      c) check_one "Layer C" "$HW_FEATURES_OUTPUT" render_hw_clean || rc=1 ;;
      all)
        check_one "Layer A" "$OUTPUT_FILE" render_clean || rc=1
        check_one "Layer C" "$HW_FEATURES_OUTPUT" render_hw_clean || rc=1
        ;;
    esac
    exit "$rc"
    ;;
esac
