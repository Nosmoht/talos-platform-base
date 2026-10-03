#!/usr/bin/env bash
set -uo pipefail

FIXTURES="schemas/fixtures/bootstrap"
OUT="kubernetes/bootstrap/argocd/_out"
fail=0

die_env() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 2
}

command -v yq >/dev/null 2>&1 || die_env "yq not on PATH"
command -v envsubst >/dev/null 2>&1 || die_env "envsubst not on PATH"
command -v task >/dev/null 2>&1 || die_env "task not on PATH"
[ -d "$FIXTURES" ] || die_env "fixture dir $FIXTURES missing"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

render() {
  rm -rf "$OUT"
  task bootstrap:render-root ENV="$1" 2>&1
}

pass() { printf '  ok   — %s\n' "$1"; }
bad()  { printf '  FAIL — %s\n' "$1" >&2; fail=1; }

printf 'happy path\n'
[ -f "$FIXTURES/valid.yaml" ] || die_env "missing $FIXTURES/valid.yaml"
if ! out=$(render "$FIXTURES/valid.yaml"); then
  bad "valid fixture did not render"
  printf '%s\n' "$out" >&2
else
  app="$OUT/root-application.yaml"
  proj="$OUT/root-project.yaml"
  if [ ! -f "$app" ] || [ ! -f "$proj" ]; then
    bad "render reported success but did not write both manifests"
  else
    want_in() {
      if grep -qF "$2" "$1"; then pass "$3"; else bad "$3 — not found: $2"; fi
    }
    want_in "$app"  'repoURL: https://example.invalid/consumer-repo.git' "repo.url reaches the root Application"
    want_in "$app"  'path: kubernetes/overlays/prod'                     "cluster.overlay reaches the root Application"
    want_in "$app"  'app.kubernetes.io/instance: fixture-cluster'        "cluster.name reaches the root Application"
    want_in "$proj" 'https://example.invalid/consumer-repo.git'          "repo.url reaches the AppProject sourceRepos"
    want_in "$app"  'targetRevision: main'                               "absent target_revision defaults to main"
    cp "$app" "$tmp/valid-app.yaml"
    cp "$proj" "$tmp/valid-proj.yaml"
  fi
fi

printf 'differential (no other field influences the output)\n'
if [ -f "$tmp/valid-app.yaml" ]; then
  if ! out=$(render "$FIXTURES/twin.yaml"); then
    bad "twin fixture did not render"
    printf '%s\n' "$out" >&2
  else
    if diff -q "$tmp/valid-app.yaml" "$OUT/root-application.yaml" >/dev/null \
       && diff -q "$tmp/valid-proj.yaml" "$OUT/root-project.yaml" >/dev/null; then
      pass "a cluster.yaml differing in every non-identity field renders identically"
    else
      bad "a non-identity field influenced the rendered output"
      diff "$tmp/valid-app.yaml" "$OUT/root-application.yaml" >&2 || true
      diff "$tmp/valid-proj.yaml" "$OUT/root-project.yaml" >&2 || true
    fi
  fi
fi

reject() {
  desc="$1"; fixture="$2"; want="$3"
  if [ ! -f "$fixture" ]; then die_env "missing fixture $fixture"; fi
  out=$(render "$fixture")
  rc=$?
  if [ "$rc" -eq 0 ]; then
    bad "$desc — render SUCCEEDED; the guard does not bite"
    return
  fi
  if [ -e "$OUT" ]; then
    bad "$desc — rejected but left $OUT behind"
    return
  fi
  if [ -n "$want" ] && ! printf '%s' "$out" | grep -qF "$want"; then
    bad "$desc — rejected, but not for the stated reason (expected: $want)"
    printf '%s\n' "$out" >&2
    return
  fi
  pass "$desc"
}

printf 'containment guards\n'
reject "a \$-bearing value is rejected"          "$FIXTURES/inject-dollar.yaml"          "unsafe for envsubst"
reject "a newline-bearing value is rejected"     "$FIXTURES/inject-newline.yaml"         "control character"
reject "a CR-bearing value is rejected"          "$FIXTURES/inject-carriage-return.yaml" "control character"
reject "an empty value is rejected"              "$FIXTURES/empty-overlay.yaml"          "is empty"
reject "a non-scalar value is rejected"          "$FIXTURES/inject-non-scalar.yaml"      "no matches found"
reject "a path-traversing overlay is rejected"   "$FIXTURES/traverse-overlay.yaml"       "single lowercase kustomize directory name"
reject "a YAML-quoting value is rejected"        "$FIXTURES/inject-yaml-quoting.yaml"    "does not survive a YAML round-trip"
reject "a whitespace-only value is rejected"     "$FIXTURES/blank-overlay.yaml"          "does not survive a YAML round-trip"

printf 'missing identity fields (omit x null, three fields)\n'
for path in '.cluster.name' '.repo.url' '.cluster.overlay'; do
  for mode in omit null; do
    f="$tmp/missing$(printf '%s' "$path" | tr -d '.').$mode.yaml"
    if [ "$mode" = omit ]; then
      yq "del($path)" "$FIXTURES/valid.yaml" > "$f" || die_env "yq failed building fixture $f"
    else
      yq "$path = null" "$FIXTURES/valid.yaml" > "$f" || die_env "yq failed building fixture $f"
    fi
    reject "$path $mode → render fails, no manifest" "$f" ""
  done
done

printf 'envsubst allowlist (template-side containment)\n'
probe_src="kubernetes/bootstrap/argocd/root-application.yaml.tmpl"
[ -f "$probe_src" ] || die_env "missing $probe_src"
probe="$tmp/probe.tmpl"
cp "$probe_src" "$probe"
# shellcheck disable=SC2016  # literal $NOT_ALLOWLISTED is the point: it must NOT expand here
printf '\n# leak-probe: $NOT_ALLOWLISTED\n' >> "$probe"

export CLUSTER_NAME=fixture-cluster REPO_URL=https://example.invalid/r.git \
       OVERLAY=prod TARGET_REVISION=main TARGET_REVISION_LABEL=main \
       NOT_ALLOWLISTED=leaked-host-value
# shellcheck disable=SC2016  # single quotes are required: this is envsubst's SHELL-FORMAT allowlist, not a shell expansion
envsubst '$CLUSTER_NAME $REPO_URL $OVERLAY $TARGET_REVISION $TARGET_REVISION_LABEL' \
  < "$probe" > "$tmp/probe.out" || die_env "probe render failed"

# shellcheck disable=SC2016  # the literal $NOT_ALLOWLISTED sequence IS the assertion; it must not expand
if grep -qF 'leaked-host-value' "$tmp/probe.out"; then
  bad "host environment leaked into the rendered manifest — the allowlist is not constraining template expansion"
elif grep -qF '$NOT_ALLOWLISTED' "$tmp/probe.out"; then
  pass "a non-allowlisted \$NAME in a template stays literal"
else
  bad "probe inconclusive: the sequence is neither literal nor expanded"
  cat "$tmp/probe.out" >&2
fi

allowlisted_calls=$(grep -cF "envsubst '\$" Taskfile.yml || true)
total_calls=$(grep -cE '(^ *|[|;&(] *)envsubst ' Taskfile.yml || true)
if [ "${allowlisted_calls:-0}" -ge 2 ] && [ "${allowlisted_calls:-0}" -eq "${total_calls:-0}" ]; then
  pass "every envsubst call in Taskfile.yml passes a SHELL-FORMAT allowlist ($allowlisted_calls/$total_calls)"
else
  bad "an envsubst call without a SHELL-FORMAT allowlist exists ($allowlisted_calls/$total_calls allowlisted) — template-side containment is gone"
fi

rm -rf "$OUT"

if [ "$fail" -ne 0 ]; then
  printf '\nFAIL: bootstrap render does not satisfy openspec/specs/argocd-day-zero-bootstrap\n' >&2
  exit 1
fi
printf '\nOK: bootstrap render satisfies the argocd-day-zero-bootstrap scenarios\n'
