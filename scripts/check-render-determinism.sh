#!/usr/bin/env bash
# Regression fence for #123 (talos-cluster render -> machineConfig decoupling).
#
# data.helm_template renders are re-evaluated every plan and are NOT byte-stable
# (Sprig genCA at template time; helm-provider ordering). Consumed directly, every
# plan / Crossplane reconcile re-pushed a fresh machineConfig (#121). The fix
# freezes each render in state via a terraform_data carrying
# lifecycle { ignore_changes = [input] }; the ArgoCD-CRD render (a Day-2 kubectl
# convergence) additionally carries triggers_replace so an INTENDED chart/version
# bump still re-applies.
#
# This guard fails if that decoupling regresses. It does NOT use a hardcoded render
# allow-list: it derives every `data "helm_template" "<r>"` from the file and, for
# each, asserts:
#   1. the live render is referenced exactly once — either directly as the `input =`
#      capture of its terraform_data.<r>_render freeze, or once inside a top-level
#      locals{} block whose value that freeze then captures (`input = local.*`).
#      The second shape admits a pure transform between read and freeze (#218
#      projects the ArgoCD render down to its CRD documents, so the frozen bytes are
#      exactly what kubectl applies) without weakening the property: still ONE live
#      read, and every apply-path consumer still goes through the freeze. A
#      contents=/content=/sha256() consumer, or any second reference, re-introduces
#      the #121 drift and still fails;
#   2. that freeze resource exists AND its OWN block carries ignore_changes=[input]
#      (per-resource, so a broken freeze cannot be masked by a decoy elsewhere);
#   3. CRD renders (name matches *crds*, a Day-2 kubectl re-apply path) additionally
#      carry triggers_replace, so deleting it (silent-non-apply on an intended bump)
#      is caught.
#
# Hermetic: pure static analysis of main.tf, no providers/network. Wired into
# `task tofu:ci`. Usage: scripts/check-render-determinism.sh [path/to/main.tf]
#
# NOTE (acknowledged limit): check (3) asserts triggers_replace is PRESENT, not that
# it ENUMERATES every render-affecting input of the data source. A render input added
# to the data source but not to triggers_replace is a silent-non-apply the static
# guard cannot see — the code comment on the freeze is the binding, keep it honest.
set -euo pipefail

MAIN="${1:-tofu/modules/talos-cluster/main.tf}"

if [ ! -f "$MAIN" ]; then
  echo "::error::check-render-determinism: ${MAIN} not found" >&2
  exit 1
fi

# Print the top-level resource block for terraform_data."<name>" (resource opens at
# column 0 and its closing brace is the first subsequent line starting with `}`).
block_of() {
  awk -v name="$1" '
    index($0, "resource \"terraform_data\" \"" name "\"") == 1 { inb = 1 }
    inb { print }
    inb && /^}/ { inb = 0 }
  ' "$MAIN"
}

# Does the single live-render reference sit inside a top-level `locals {` block?
# Column-0 block model: a top-level block opens at column 0 and closes at the
# first subsequent line whose first character is `}`. Comment lines are skipped
# BEFORE the membership test so a `#`-quoted mention cannot decide the verdict.
# Prints "yes" / "no" (empty when the pattern does not occur).
ref_inside_locals() {
  awk -v pat="$1" '
    /^[[:space:]]*#/              { next }
    /^locals[[:space:]]*\{/       { inloc = 1; next }
    /^[a-z][a-zA-Z_]*[[:space:]]/ { inloc = 0 }
    /^}/                          { inloc = 0; next }
    index($0, pat) > 0            { print (inloc ? "yes" : "no"); exit }
  ' "$MAIN"
}

# Names defined in the top-level locals{} block(s), one per line. Used to trace
# which locals could be carrying a live render downstream.
locals_names() {
  awk '
    /^[[:space:]]*#/              { next }
    /^locals[[:space:]]*\{/       { inloc = 1; next }
    /^}/                          { inloc = 0; next }
    inloc && match($0, /^[[:space:]]+[a-z_][a-zA-Z0-9_]*[[:space:]]*=/) {
      s = $0; sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]*=.*$/, "", s); print s
    }
  ' "$MAIN"
}

# Lines OUTSIDE every top-level locals{} block, comments stripped. The apply-path
# scan below runs over these: inside locals a value is still just a value, but
# outside it is wired to something that writes or executes.
lines_outside_locals() {
  awk '
    /^[[:space:]]*#/              { next }
    /^locals[[:space:]]*\{/       { inloc = 1; next }
    /^}/                          { if (inloc) { inloc = 0; next } }
    !inloc                        { print }
  ' "$MAIN"
}

fail=0

# Derive every helm render present in the module — not a hardcoded list, so a future
# render path cannot slip past the fence by simply not being named here.
renders=$(grep -oE 'data "helm_template" "[a-z_]+"' "$MAIN" | sed -E 's/.*"([a-z_]+)"$/\1/' | sort -u)
if [ -z "$renders" ]; then
  echo "::error::check-render-determinism: no data \"helm_template\" found in ${MAIN} — fence assumptions broken (did the module move?)." >&2
  exit 1
fi

count=0
for r in $renders; do
  count=$((count + 1))

  # (1) live render referenced exactly once. Two accepted capture shapes:
  #     (a) DIRECT   — `input = data.helm_template.<r>[0].manifest` on the freeze;
  #     (b) PROJECTED — the single reference sits in a top-level locals{} block and
  #         the freeze captures a local (`input = local.<name>`). This admits a pure,
  #         deterministic transform between read and freeze — #218 projects the
  #         ArgoCD render down to its CRD documents there, so the frozen bytes are
  #         exactly what kubectl applies. The #123 property is unchanged either way:
  #         ONE live read, and every apply-path consumer goes through the freeze.
  #     Anything else (a second reference, a contents=/sha256() consumer) still fails.
  total=$(grep -cE "data\.helm_template\.${r}\[0\]\.manifest" "$MAIN" || true)
  capture=$(grep -cE "^[[:space:]]*input[[:space:]]+= data\.helm_template\.${r}\[0\]\.manifest" "$MAIN" || true)
  blk=$(block_of "${r}_render")
  projected=0
  if [ "$capture" -eq 0 ] && [ "$total" -eq 1 ] && [ -n "$blk" ] &&
    [ "$(ref_inside_locals "data.helm_template.${r}[0].manifest")" = "yes" ] &&
    printf '%s\n' "$blk" | grep -qE '^[[:space:]]*input[[:space:]]+= local\.'; then
    projected=1
  fi

  # The PROJECTED shape admits a transform, so "referenced once as input=" no
  # longer implies "no consumer reaches the live render". Re-establish the second
  # half explicitly: no local defined in the locals{} block may reach an
  # apply-path sink outside it. Without this a one-line change —
  #   resource "local_file" "x" { content = local.<the projection> }
  # — passes the three checks above while handing the non-byte-stable live render
  # straight to kubectl, which is the #121/#123 defect this fence exists for.
  # Sinks are the attributes that write or execute: content(s), command, and any
  # sha256() (the re-apply trigger). `input =` on the freeze is the sanctioned
  # consumer and is excluded by matching the sink attributes, not by name.
  if [ "$projected" -eq 1 ]; then
    outside="$(lines_outside_locals)"
    while IFS= read -r lname; do
      [ -n "$lname" ] || continue
      if printf '%s\n' "$outside" |
        grep -E '(content[s]?[[:space:]]*=|command[[:space:]]*=|sha256\()' |
        grep -qE "local\.${lname}([^a-zA-Z0-9_]|\$)"; then
        echo "::error::check-render-determinism: local.${lname} — which may derive from the live data.helm_template.${r} render — reaches an apply-path sink (content/contents/command/sha256) outside the locals block. Every apply-path consumer must read terraform_data.${r}_render[0].output instead, or the non-byte-stable render is re-pushed on every plan (#121/#123)." >&2
        fail=1
      fi
    done <<EOF
$(locals_names)
EOF

    # The sink scan above is ONE HOP: it matches a sink attribute on a line that
    # literally names `local.<x>`. That leaves an indirect launder — freeze the
    # projection in a SECOND terraform_data, then read its `.output` from a sink.
    # No sink line mentions `local.`, so the scan never sees it, and the live
    # render reaches kubectl unfrozen: the #121/#123 defect one resource away.
    #
    # `input =` is the sanctioned consumer, but only ON THE FREEZE. Assert that:
    # any other block capturing the projection is itself a sink.
    while IFS= read -r cap; do
      [ -n "$cap" ] || continue
      [ "$cap" = "${r}_render" ] && continue
      echo "::error::check-render-determinism: resource terraform_data.${cap} captures a locals value derived from the live data.helm_template.${r} render via input =. That value may be captured only by terraform_data.${r}_render — a second freeze is an indirect apply-path sink: its .output reaches kubectl without ever passing the sanctioned freeze (#121/#123)." >&2
      fail=1
    done <<EOF
$(awk '
    /^resource "terraform_data" "/ { name = $0; sub(/^resource "terraform_data" "/, "", name); sub(/".*$/, "", name); inb = 1; next }
    inb && /^[[:space:]]*input[[:space:]]+= local\./ { print name }
    inb && /^}/ { inb = 0 }
  ' "$MAIN")
EOF
  fi

  if [ "$total" -ne 1 ] || { [ "$capture" -ne 1 ] && [ "$projected" -ne 1 ]; }; then
    echo "::error::check-render-determinism: data.helm_template.${r} must be referenced exactly once — either as the input= capture of terraform_data.${r}_render, or once inside a locals{} block whose value that freeze captures via input = local.* (found total=${total}, capture=${capture}, projected=${projected}). A direct consumer (contents=/content=/sha256()) or an unmatched reference shape re-introduces the #123 machineConfig re-push — route it through terraform_data.${r}_render[0].output." >&2
    fail=1
  fi

  # (2) freeze exists AND its OWN block carries ignore_changes=[input].
  if [ -z "$blk" ]; then
    echo "::error::check-render-determinism: freeze resource terraform_data.${r}_render is missing in ${MAIN} (#123)." >&2
    fail=1
    continue
  fi
  if ! printf '%s\n' "$blk" | grep -qE '^[[:space:]]*ignore_changes[[:space:]]*=[[:space:]]*\[input\]'; then
    echo "::error::check-render-determinism: terraform_data.${r}_render block lacks lifecycle { ignore_changes = [input] } — the freeze is broken and the render would re-capture every plan (#123)." >&2
    fail=1
  fi

  # (3) CRD renders feed a Day-2 kubectl re-apply and MUST re-capture on an intended
  #     bump — deleting triggers_replace turns the convergence path into a frozen
  #     seed (silent-non-apply). Seed renders intentionally have no triggers_replace.
  case "$r" in
    *crds*)
      if ! printf '%s\n' "$blk" | grep -qE '^[[:space:]]*triggers_replace[[:space:]]*='; then
        echo "::error::check-render-determinism: terraform_data.${r}_render (a Day-2 CRD kubectl-apply path) must carry triggers_replace so an intended chart/version bump re-applies; without it an intended bump silently never re-applies (#123)." >&2
        fail=1
      fi
      ;;
  esac
done

if [ "$fail" -eq 0 ]; then
  echo "check-render-determinism: OK — ${count} helm render(s) consumed only via frozen terraform_data (ignore_changes); CRD render(s) carry triggers_replace."
fi
exit "$fail"
