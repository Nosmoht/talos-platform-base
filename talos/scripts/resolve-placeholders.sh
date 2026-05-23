#!/usr/bin/env bash
# resolve-placeholders.sh — substitute ${PLACEHOLDER} tokens in a patch file
# using bindings supplied by the caller.
#
# Usage: resolve-placeholders.sh <patch-file> <bindings-file>
#
#   <patch-file>     Path to a YAML patch file (may contain ${NAME} tokens).
#   <bindings-file>  TAB-separated PLACEHOLDER<TAB>VALUE per line.
#
# Output: rendered patch on stdout. Exits 1 if any token in the patch is
# referenced but absent from the bindings file. Designed to be called from
# argv-print.sh per-patch-per-node.
#
# Security: substitutions are literal — never invokes envsubst or eval, so
# attacker-controlled bindings cannot reach shell execution. Placeholder
# names are constrained to ^[A-Z][A-Z0-9_]*$ at the bindings-build site
# (caller's responsibility; verified by validate-schematics' charset guard).
#
# Requires: bash 3.2+, sed, grep.

set -euo pipefail

PATCH_FILE="${1:?Usage: $0 <patch-file> <bindings-file>}"
BINDINGS_FILE="${2:?bindings-file required}"

[[ -f "$PATCH_FILE" ]] || { echo "ERROR: patch file not found: $PATCH_FILE" >&2; exit 1; }
[[ -f "$BINDINGS_FILE" ]] || { echo "ERROR: bindings file not found: $BINDINGS_FILE" >&2; exit 1; }

# Collect every ${NAME} token referenced in the patch.
REFS=$(grep -oE '\$\{[A-Z][A-Z0-9_]*\}' "$PATCH_FILE" 2>/dev/null | sort -u || true)

# Build a sed script that maps each known binding to its value. Values are
# sed-escaped: we use a delimiter unlikely to collide ('|') and escape the
# four metacharacters sed treats specially in the replacement RHS (\, &, |, newline).
SED_SCRIPT=""
while IFS=$'\t' read -r name value; do
    [[ -z "$name" ]] && continue
    # Charset guard on binding name (defense-in-depth — caller should already enforce).
    if ! [[ "$name" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
        echo "ERROR: binding name '$name' violates ^[A-Z][A-Z0-9_]*\$ (refusing to substitute)" >&2
        exit 1
    fi
    # Reject multi-line values — placeholders resolve to short scalar identifiers
    # (NIC names, disk paths, WWIDs), never multi-line content. Keeping this an
    # error avoids the BSD-sed newline-collapse trap (where the GNU-style ':a;N;$!ba'
    # pattern silently produces empty output on BSD sed when stdin has no trailing
    # newline).
    if [[ "$value" == *$'\n'* ]]; then
        echo "ERROR: binding value for '$name' contains newline (multi-line bindings not supported)" >&2
        exit 1
    fi
    # Escape sed RHS metacharacters: backslash, ampersand, delimiter.
    esc=$(printf '%s' "$value" | sed 's/[\\&|]/\\&/g')
    SED_SCRIPT+="s|\\\${${name}}|${esc}|g;"
done < "$BINDINGS_FILE"

# Apply the substitutions, then verify no ${...} token remains.
if [[ -n "$SED_SCRIPT" ]]; then
    RENDERED=$(sed -E "$SED_SCRIPT" "$PATCH_FILE")
else
    RENDERED=$(cat "$PATCH_FILE")
fi

UNRESOLVED=$(printf '%s' "$RENDERED" | grep -oE '\$\{[A-Z][A-Z0-9_]*\}' | sort -u || true)
if [[ -n "$UNRESOLVED" ]]; then
    echo "ERROR: unresolved placeholders in $PATCH_FILE:" >&2
    echo "$UNRESOLVED" >&2
    echo "(checked against $(wc -l < "$BINDINGS_FILE" | tr -d ' ') binding(s) in $BINDINGS_FILE)" >&2
    if [[ -n "$REFS" ]]; then
        echo "Patch references: $(echo "$REFS" | tr '\n' ' ')" >&2
    fi
    exit 1
fi

printf '%s\n' "$RENDERED"
