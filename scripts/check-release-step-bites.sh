#!/usr/bin/env bash
# check-release-step-bites.sh — proves oci-publish.yml's release steps bite.
#
# The two steps under test create the GitHub Release. They only ever run on a
# `v*` tag push, and a published release is immutable: getting them wrong costs
# a version, which is how five tags shipped without their assets (#251). So
# they are exercised here, against a stub `gh`, on every PR instead.
#
# The three disciplines scripts/check-release-guard-gate-bites.sh records:
#
#   1. Assert the state the scenario claims to have built BEFORE reading a
#      verdict, so it cannot pass because its setup silently failed.
#   2. Assert the OBSERVABLE, not just the exit code — here the ORDER of the
#      `gh` calls, because "created a release" and "created a release the assets
#      reached before it was published" have the same exit status and only the
#      second survives immutability.
#   3. Cover BOTH directions of a rule. A green case alone is satisfied by a
#      step that never fails; a red case alone by one that never succeeds.
#
# The scripts under test are EXTRACTED FROM THE WORKFLOW, never copied here: a
# copy would keep passing after the workflow changed. Extraction is asserted to
# have found real content, so a reformatted workflow fails loudly.
#
# Runs offline, mutates nothing outside its temp dir.
# Exit 0 = both steps behaved, 1 = a step regressed, 2 = environment error.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WF="${ROOT}/.github/workflows/oci-publish.yml"
[ -r "$WF" ] || { printf 'ERROR: %s not readable\n' "$WF" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

rc=0
scenarios=0
note() { printf 'FAIL: %s\n' "$*" >&2; rc=1; }
ok() { printf '  ok   %s\n' "$*"; scenarios=$((scenarios + 1)); }

# ---------------------------------------------------------------------------
# extract the two `run:` bodies by indentation
# ---------------------------------------------------------------------------
extract_step() {
  # $1 = step name, $2 = output path. Steps are indented 6, step keys 8, and a
  # block scalar's content 10.
  awk -v want="      - name: $1" '
    $0 == want { in_step = 1; next }
    in_step && /^      - / { exit }
    in_step && $0 == "        run: |" { in_run = 1; next }
    in_run && /^          / { sub(/^          /, ""); print; next }
    in_run && /^[[:space:]]*$/ { print ""; next }
    in_run { exit }
  ' "$WF" > "$2"
  [ -s "$2" ] || { printf 'ERROR: extracted no script for step "%s" — the workflow indentation changed\n' "$1" >&2; exit 2; }
}

extract_step "Create GitHub Release" "$WORK/create.sh"
extract_step "Assert the published release carries its assets" "$WORK/assert.sh"

grep -q 'gh release create' "$WORK/create.sh" \
  || { printf 'ERROR: the extracted create script does not call `gh release create`\n' >&2; exit 2; }
grep -q 'assets\[@\]' "$WORK/create.sh" \
  || { printf 'ERROR: the extracted create script does not pass an asset array\n' >&2; exit 2; }

for f in create.sh assert.sh; do
  if grep -q '\${{' "$WORK/$f"; then
    note "$f interpolates a \${{ }} expression into the shell — variable text belongs in the step's env: block (release.yml §notify)"
  fi
done
ok "both steps extracted; neither splices a workflow expression into the shell"

# ---------------------------------------------------------------------------
# 0) the other half of the fix, and the half nothing else watches
#
# The steps above are only correct because semantic-release no longer creates
# the release. That is an ABSENCE in .releaserc.json, and an absence has no
# test unless one is written: @semantic-release/github ships as a direct
# dependency of semantic-release and is a member of its DEFAULT plugin list,
# so anything that stops the config from being read republishes an asset-less
# release and #251 returns. Asserted here rather than in a doc.
# ---------------------------------------------------------------------------
RELEASERC="${ROOT}/.releaserc.json"
[ -r "$RELEASERC" ] || { printf 'ERROR: .releaserc.json not readable — semantic-release would fall back to its default plugin list, which publishes a GitHub Release\n' >&2; exit 2; }
if grep -q '@semantic-release/github' "$RELEASERC"; then
  note ".releaserc.json declares @semantic-release/github; it publishes the release object at tag time, before the assets exist (#251)"
else
  ok ".releaserc.json declares no GitHub publish plugin"
fi
if grep -q '"@semantic-release/github"' "${ROOT}/package.json"; then
  note "package.json takes @semantic-release/github as a direct dependency, which is a standing invitation to re-add it to the plugin list"
else
  ok "@semantic-release/github is not a direct dependency of this repository"
fi
# cosmiconfig finds .releaserc.json at the repo root; a second config file
# would shadow it, and which one wins is not worth reasoning about per PR.
other_config=""
for candidate in .releaserc .releaserc.yaml .releaserc.yml .releaserc.js \
                 .releaserc.cjs .releaserc.mjs release.config.js \
                 release.config.cjs release.config.mjs; do
  [ -e "${ROOT}/${candidate}" ] && other_config="${other_config} ${candidate}"
done
if [ -n "$other_config" ]; then
  note "a second semantic-release config is present alongside .releaserc.json:${other_config}"
else
  ok ".releaserc.json is the only semantic-release config in the repository root"
fi

# ---------------------------------------------------------------------------
# stub gh
#
#   $STATE     none | draft | published — the release object for $TAG
#   $EXTRA     a second "<id> <draft>" line the release listing also returns
#   $DROP      an asset basename `gh release create` silently fails to upload
#   $UPLOADED  what the stub has actually attached, one basename per line
#   $LOG       every call, in order
# ---------------------------------------------------------------------------
mkdir -p "$WORK/bin" "$WORK/repo/_release"
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
state="$(cat "$STATE")"
printf '%s\n' "$*" >> "$LOG"

# the release listing
if [ "$1" = "api" ] && [ "$2" = "--paginate" ]; then
  case "$state" in
    draft) printf '%s\n' "4242 true" ;;
    published) printf '%s\n' "4242 false" ;;
  esac
  [ -n "${EXTRA:-}" ] && printf '%s\n' "$EXTRA"
  # a release that appears only AFTER `gh release create` has run — the
  # interleaving the post-create checks exist for
  [ -n "${EXTRA_AFTER:-}" ] && [ -f "$CREATED_FLAG" ] && printf '%s\n' "$EXTRA_AFTER"
  exit 0
fi

if [ "$1" = "api" ] && [ "$2" = "--method" ]; then
  case "$3" in
    DELETE) printf 'none\n' > "$STATE"; : > "$UPLOADED" ;;
    PATCH)  printf 'published\n' > "$STATE"; printf '%s\n' "https://example.invalid/releases/4242" ;;
  esac
  exit 0
fi

if [ "$1" = "release" ] && [ "$2" = "create" ]; then
  # the real gh refuses a missing asset path, and so must the stub: a step
  # naming the wrong file must not pass here and fail on a real tag.
  : > "$UPLOADED"
  for a in "$@"; do
    case "$a" in
      _release/*)
        [ -f "$a" ] || { printf 'gh: asset %s does not exist\n' "$a" >&2; exit 1; }
        base="${a##*/}"
        [ "$base" = "${DROP:-}" ] || printf '%s\n' "$base" >> "$UPLOADED"
        ;;
    esac
  done
  : > "$CREATED_FLAG"
  case " $* " in
    *" --draft "*) printf 'draft\n' > "$STATE" ;;
    *) printf 'published\n' > "$STATE" ;;   # the pre-fix behaviour
  esac
  exit 0
fi

# an asset listing: by release id (pre-publish) or by tag (post-publish)
if [ "$1" = "api" ]; then
  case "$2" in
    */releases/tags/*)
      [ "$state" = "published" ] || { printf 'gh: release not found\n' >&2; exit 1; }
      ;;
  esac
  sort "$UPLOADED"
  exit 0
fi
exit 0
STUB
chmod +x "$WORK/bin/gh"

export PATH="$WORK/bin:$PATH"
export GITHUB_REPOSITORY="owner/talos-platform-base"
export GH_TOKEN="stub-token-not-a-credential"
export LOG="$WORK/log" STATE="$WORK/state" UPLOADED="$WORK/uploaded"
export CREATED_FLAG="$WORK/created"

cd "$WORK/repo"
printf '# Changelog\n\n## v9.9.9 — 2026-01-01\n\nthe section for this tag\n\n## v9.9.8 — 2025-12-01\n\nolder\n' > CHANGELOG.md

# one token per call: L list · C create · D delete · A assets-by-id
# · T assets-by-tag · P publish
call_order() {
  awk '
    /^api --paginate/                      { printf "L"; next }
    /^release create/                      { printf "C"; next }
    /^api --method DELETE/                 { printf "D"; next }
    /^api --method PATCH/                  { printf "P"; next }
    /^api repos\/[^ ]*\/releases\/tags\//  { printf "T"; next }
    /^api repos\/[^ ]*\/releases\/[0-9]/   { printf "A"; next }
  ' "$LOG"
  printf '\n'
}

run_create() {
  local start_state="$1" tag="$2"
  printf '%s\n' "$start_state" > "$STATE"
  : > "$LOG"
  : > "$UPLOADED"
  rm -f "$CREATED_FLAG"
  export TAG="$tag"
  rm -f _release/*
  touch "_release/talos-platform-base-${tag}.tar.gz" "_release/checksums.txt" \
        "_release/talos-platform-base-${tag}.cdx.json"
  [ "$(cat "$STATE")" = "$start_state" ] || { printf 'ERROR: scenario setup failed\n' >&2; exit 2; }
  bash "$WORK/create.sh" > "$WORK/out" 2>&1
}

unset EXTRA DROP

# --- 1) no release yet: draft, assets, verified, published last -------------
if run_create none v9.9.9; then
  order="$(call_order)"
  [ "$order" = "LCLAP" ] \
    && ok "no release yet → create draft, verify its assets, publish last ($order)" \
    || note "expected call order LCLAP (list, create, list, assets, publish), got '$order'"
  grep -q -- '--draft' "$LOG" \
    && ok "the release is created as a draft" \
    || note "the release was not created with --draft — a published release refuses assets"
  [ "$(cat "$STATE")" = "published" ] \
    && ok "the release ends up published" \
    || note "the release was left in state '$(cat "$STATE")'"
  grep -q 'talos-platform-base-v9.9.9.cdx.json' "$LOG" \
    && ok "all three assets reach the create call" \
    || note "the SBOM asset did not reach the create call"
  grep -q -- '--notes-file' "$LOG" \
    && ok "notes come from the matching CHANGELOG section" \
    || note "the CHANGELOG section for the tag was not used for the notes"
  grep -q 'make_latest=legacy' "$LOG" \
    && ok "a release tag publishes with make_latest=legacy, not a last-writer-wins flag" \
    || note "a release tag did not publish with make_latest=legacy"
else
  note "the create step failed on a tag with no existing release: $(cat "$WORK/out")"
fi

# --- 2) leftover draft from a failed run: discarded and rebuilt --------------
if run_create draft v9.9.9; then
  order="$(call_order)"
  [ "$order" = "LDCLAP" ] \
    && ok "leftover draft → discarded, rebuilt, published ($order)" \
    || note "expected call order LDCLAP on a leftover draft, got '$order'"
else
  note "the create step failed on a leftover draft, so a re-run cannot recover: $(cat "$WORK/out")"
fi

# --- 3) already published: refuse, before touching anything -----------------
if run_create published v9.9.9; then
  note "the create step accepted an already-published release — every asset upload would 422"
else
  ok "an already-published release is refused rather than uploaded to"
  order="$(call_order)"
  [ "$order" = "L" ] \
    && ok "the refusal happens before any create, delete or publish call ($order)" \
    || note "expected only a list call before refusing, got '$order'"
  grep -qi 'immutable' "$WORK/out" \
    && ok "the refusal names immutability as the cause" \
    || note "the refusal does not tell the reader why it cannot proceed"
  grep -q 'release-process.md' "$WORK/out" \
    && ok "the refusal points at the recovery section" \
    || note "the refusal names no recovery procedure"
fi

# --- 3b) a draft beside a published release must not read as "just a draft" -
export EXTRA="4243 false"
if run_create draft v9.9.9; then
  note "a draft sitting beside a PUBLISHED release for the same tag was treated as recoverable"
else
  ok "a published release is detected even when a draft for the tag also exists"
fi
unset EXTRA

# --- 3b2) ... and one that appears only after the draft was created ---------
export EXTRA_AFTER="4243 false"
if run_create none v9.9.9; then
  note "a release published while the draft was being built was ignored, and the publish call aimed at the first listed release"
else
  ok "a release published mid-run is caught by the post-create check too"
  grep -q -- '--method PATCH' "$LOG" \
    && note "the step patched a release anyway after detecting the interleaving" \
    || ok "nothing was published once the interleaving was detected"
fi
unset EXTRA_AFTER

# --- 3c) two drafts: refuse rather than orphan one --------------------------
export EXTRA="4243 true"
if run_create draft v9.9.9; then
  note "two drafts for one tag: the step deleted one and orphaned the other"
else
  grep -qi 'more than one draft' "$WORK/out" \
    && ok "two drafts for one tag are refused rather than silently orphaned" \
    || note "two drafts were refused, but not for the stated reason: $(cat "$WORK/out")"
fi
unset EXTRA

# --- 4) an asset that fails to upload: caught while still recoverable -------
export DROP="talos-platform-base-v9.9.9.cdx.json"
if run_create none v9.9.9; then
  note "a draft missing the SBOM was published — the release is now immutable and incomplete"
else
  ok "a draft missing an asset is not published"
  order="$(call_order)"
  case "$order" in
    *P*) note "the step published the release anyway (order '$order')" ;;
    *A*) ok "the failure lands after the asset check and before the publish call ($order)" ;;
    *) note "expected an asset check before the failure, got '$order'" ;;
  esac
  [ "$(cat "$STATE")" = "draft" ] \
    && ok "the incomplete release is left as a discardable draft" \
    || note "the incomplete release was left in state '$(cat "$STATE")'"
fi
unset DROP

# --- 5) a pre-release tag stays off :latest ---------------------------------
if run_create none v9.9.9-rc.1; then
  grep -q -- '--prerelease' "$LOG" \
    && ok "a hyphenated tag is marked pre-release" \
    || note "a hyphenated tag was not marked pre-release"
  grep -q 'make_latest=false' "$LOG" \
    && ok "a hyphenated tag does not become the latest release" \
    || note "a hyphenated tag would be published as the latest release"
  grep -q -- '--generate-notes' "$LOG" \
    && ok "a tag with no CHANGELOG section falls back to generated notes" \
    || note "the notes fallback did not fire for a tag with no CHANGELOG section"
else
  note "the create step failed on a pre-release tag: $(cat "$WORK/out")"
fi

# --- 6) the end-state assertion, both directions ---------------------------
run_assert() {
  export TAG=v9.9.9
  printf 'published\n' > "$STATE"
  : > "$LOG"
  printf '%s\n' $1 > "$UPLOADED"
  bash "$WORK/assert.sh" > "$WORK/out" 2>&1
}

if run_assert "checksums.txt talos-platform-base-v9.9.9.cdx.json talos-platform-base-v9.9.9.tar.gz"; then
  ok "the end-state assertion passes on a release carrying all three assets"
else
  note "the end-state assertion rejected a complete release: $(cat "$WORK/out")"
fi
if run_assert "checksums.txt talos-platform-base-v9.9.9.tar.gz"; then
  note "the end-state assertion passed on a release missing the SBOM"
else
  ok "the end-state assertion fails on a release missing one asset"
fi
if run_assert ""; then
  note "the end-state assertion passed on an asset-less release — the very defect it exists to catch"
else
  ok "the end-state assertion fails on an asset-less release"
fi
if run_assert "checksums.txt talos-platform-base-v9.9.9.cdx.json talos-platform-base-v9.9.9.tar.gz extra.txt"; then
  note "the end-state assertion passed on a release carrying an unexpected extra asset"
else
  ok "the end-state assertion fails on an unexpected extra asset"
fi
[ "$(call_order)" = "T" ] \
  && ok "the end-state assertion reads the release through the tag endpoint consumers use" \
  || note "the end-state assertion did not read the tag endpoint"

# ---------------------------------------------------------------------------
[ "$rc" -eq 0 ] || exit 1
# A floor, not a description: narrowing the suite has to fail here rather than
# quietly report a smaller number.
if [ "$scenarios" -lt 25 ]; then
  printf 'FAIL: only %d scenarios ran; the suite has been narrowed\n' "$scenarios" >&2
  exit 1
fi
printf 'release-step bite-check OK (%d scenarios)\n' "$scenarios"
