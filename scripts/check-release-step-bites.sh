#!/usr/bin/env bash

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

extract_step() {
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
ok "both steps extracted"

interpolated="$(awk '
  match($0, /^[[:space:]]*run:[[:space:]]*\|/) {
    key = index($0, "run:") - 1; in_run = 1; next
  }
  match($0, /^[[:space:]]*run:[[:space:]]*[^|>[:space:]]/) {
    in_run = 0
    if ($0 ~ /\$\{\{/) print FILENAME ":" FNR ": " $0
    next
  }
  in_run {
    if ($0 ~ /^[[:space:]]*$/) next
    ind = match($0, /[^[:space:]]/) - 1
    if (ind <= key) { in_run = 0; next }
    if ($0 ~ /\$\{\{/) print FILENAME ":" FNR ": " $0
  }
' "$WF")"
if [ -n "$interpolated" ]; then
  note "a run: block interpolates a workflow expression into the shell:"
  printf '%s\n' "$interpolated" >&2
else
  ok "no run: block in the workflow splices a workflow expression into the shell"
fi

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

mkdir -p "$WORK/bin" "$WORK/repo/_release"
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
state="$(cat "$STATE")"
printf '%s\n' "$*" >> "$LOG"

# the release listing
if [ "$1" = "api" ] && [ "$2" = "--paginate" ]; then
  # The listing has not caught up with the create yet. The lag hides only THIS
  # run's own release (4242): a foreign release the listing already knows about
  # stays visible, which is the state that separates "wait for ours" from
  # "publish somebody else's".
  # the listing call itself fails — a 5xx from a degraded replica, a secondary
  # rate limit. Indistinguishable from a lag in its effect on the step, and it
  # must not be distinguishable in its outcome either.
  if [ -n "${LIST_FAIL:-}" ] && [ -f "$CREATED_FLAG" ]; then
    failed="$(cat "$FAIL_SEEN" 2>/dev/null || printf '0')"
    if [ "$failed" -lt "$LIST_FAIL" ]; then
      printf '%s\n' "$((failed + 1))" > "$FAIL_SEEN"
      printf 'gh: the release listing is unavailable\n' >&2
      exit 1
    fi
  fi

  lagging=0
  if [ -n "${LIST_LAG:-}" ] && [ -f "$CREATED_FLAG" ]; then
    seen="$(cat "$LAG_SEEN" 2>/dev/null || printf '0')"
    [ "$seen" -lt "$LIST_LAG" ] && lagging=1
  fi

  # the html_url lookup — by construction only this run's own release matches
  case "$*" in
    *html_url*)
      # one attempt consumed; the tag lookup above it in the same attempt reads
      # this counter without advancing it
      [ "$lagging" = 1 ] && printf '%s\n' "$((seen + 1))" > "$LAG_SEEN"
      if [ "$lagging" = 0 ] && [ "$state" = "draft" ]; then
        printf '%s\n' "4242 true"
      fi
      exit 0
      ;;
  esac

  # the tag lookup — this run's release, plus anything else on the same tag
  if [ "$lagging" = 0 ]; then
    case "$state" in
      draft) printf '%s\n' "4242 true" ;;
      published) printf '%s\n' "4242 false" ;;
    esac
  fi
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
  # the real `gh` prints the release url, and a draft's url carries the
  # per-release `untagged-<hash>` slug the step addresses it by
  printf 'https://example.invalid/releases/tag/untagged-4242\n'
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

printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$SLEEP_LOG"\nexit 0\n' > "$WORK/bin/sleep"
chmod +x "$WORK/bin/sleep"

export PATH="$WORK/bin:$PATH"
export GITHUB_REPOSITORY="owner/talos-platform-base"
export GH_TOKEN="stub-token-not-a-credential"
export LOG="$WORK/log" STATE="$WORK/state" UPLOADED="$WORK/uploaded"
export CREATED_FLAG="$WORK/created" LAG_SEEN="$WORK/lag-seen"
export SLEEP_LOG="$WORK/slept" FAIL_SEEN="$WORK/fail-seen"

cd "$WORK/repo"
printf '# Changelog\n\n## v9.9.9 — 2026-01-01\n\nthe section for this tag\n\n## v9.9.8 — 2025-12-01\n\nolder\n' > CHANGELOG.md

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
  rm -f "$CREATED_FLAG" "$LAG_SEEN" "$FAIL_SEEN"
  : > "$SLEEP_LOG"
  export TAG="$tag"
  rm -f _release/*
  touch "_release/talos-platform-base-${tag}.tar.gz" "_release/checksums.txt" \
        "_release/talos-platform-base-${tag}.cdx.json"
  [ "$(cat "$STATE")" = "$start_state" ] || { printf 'ERROR: scenario setup failed\n' >&2; exit 2; }
  bash "$WORK/create.sh" > "$WORK/out" 2>&1
}

unset EXTRA DROP LIST_LAG LIST_FAIL

if run_create none v9.9.9; then
  order="$(call_order)"
  [ "$order" = "LCLLAP" ] \
    && ok "no release yet → create draft, verify its assets, publish last ($order)" \
    || note "expected call order LCLLAP (list, create, list, locate, assets, publish), got '$order'"
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

export LIST_LAG=2
if run_create none v9.9.9; then
  ok "a listing that lags the create is retried until the draft appears"
  [ "$(cat "$STATE")" = "published" ] \
    && ok "the release still ends up published after the lag" \
    || note "the release was left in state '$(cat "$STATE")' after a listing lag"
  grep -q 'releases/4242' "$LOG" \
    && ok "the publish call targets the release this run created" \
    || note "the publish call did not target the created release: $(grep 'PATCH' "$LOG" || echo none)"
  [ -s "$SLEEP_LOG" ] \
    && ok "the retry actually backs off between attempts" \
    || note "the retry made its attempts without waiting, so it cannot outlast a real lag"
else
  note "a listing that had not caught up with the create failed the step, leaving the tag half-released: $(cat "$WORK/out")"
fi
unset LIST_LAG

export LIST_LAG=99
if run_create none v9.9.9; then
  note "the step published a release it never located — the PATCH aimed at nothing"
else
  ok "a draft that never appears exhausts the retry and fails"
  grep -q -- '--method PATCH' "$LOG" \
    && note "the step published a release anyway after failing to locate the draft" \
    || ok "nothing is published when the draft cannot be located"
  grep -q 'is not readable as exactly one draft release' "$WORK/out" \
    && ok "the exhausted retry fails with the missing-draft error, not a masked one" \
    || note "the exhausted retry failed for an unstated reason: $(cat "$WORK/out")"
fi
unset LIST_LAG

export LIST_LAG=2 EXTRA_AFTER="4243 false"
if run_create none v9.9.9; then
  note "a release published mid-run was ignored once the listing also lagged"
else
  ok "a published release is refused even while the listing is lagging"
  grep -q -- '--method PATCH' "$LOG" \
    && note "the step published something anyway after detecting the interleaving" \
    || ok "nothing is published when the interleaving is detected"
  [ -z "$(cat "$SLEEP_LOG")" ] \
    && ok "the published release is refused on first sight, not waited out" \
    || note "the step slept before refusing a published release"
fi
unset LIST_LAG EXTRA_AFTER

export LIST_LAG=2 EXTRA_AFTER="4243 true"
if run_create none v9.9.9; then
  grep -q 'releases/4243' "$LOG" \
    && note "the step published a draft this run did not create — foreign content shipped as an official release" \
    || ok "the step published only the release it created, despite a foreign draft being visible first"
else
  ok "a foreign draft beside ours is refused rather than published"
  grep -q -- '--method PATCH' "$LOG" \
    && note "the step published something after detecting a second draft" \
    || ok "nothing is published when a second draft is present"
fi
unset LIST_LAG EXTRA_AFTER

export EXTRA_AFTER="4243 true"
if run_create none v9.9.9; then
  note "a second draft appearing beside ours was published over rather than refused"
else
  ok "a second draft for the tag is refused after the create too"
  grep -qi 'more than one draft' "$WORK/out" \
    && ok "the post-create refusal names the two-draft state the recovery table keys on" \
    || note "the post-create two-draft refusal does not match the recovery table's row: $(cat "$WORK/out")"
  grep -q -- '--method PATCH' "$LOG" \
    && note "the step published something despite two drafts" \
    || ok "nothing is published when a second draft appears after the create"
fi
unset EXTRA_AFTER

export LIST_FAIL=2
if run_create none v9.9.9; then
  ok "a listing that cannot be read at all is retried rather than half-releasing the tag"
  [ "$(cat "$STATE")" = "published" ] \
    && ok "the release still ends up published after a failed listing" \
    || note "the release was left in state '$(cat "$STATE")' after a failed listing"
else
  note "a transient listing error failed the step, leaving the tag half-released: $(cat "$WORK/out")"
fi
unset LIST_FAIL

if run_create draft v9.9.9; then
  order="$(call_order)"
  [ "$order" = "LDCLLAP" ] \
    && ok "leftover draft → discarded, rebuilt, published ($order)" \
    || note "expected call order LDCLLAP on a leftover draft, got '$order'"
else
  note "the create step failed on a leftover draft, so a re-run cannot recover: $(cat "$WORK/out")"
fi

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

export EXTRA="4243 false"
if run_create draft v9.9.9; then
  note "a draft sitting beside a PUBLISHED release for the same tag was treated as recoverable"
else
  ok "a published release is detected even when a draft for the tag also exists"
fi
unset EXTRA

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

export EXTRA="4243 true"
if run_create draft v9.9.9; then
  note "two drafts for one tag: the step deleted one and orphaned the other"
else
  grep -qi 'more than one draft' "$WORK/out" \
    && ok "two drafts for one tag are refused rather than silently orphaned" \
    || note "two drafts were refused, but not for the stated reason: $(cat "$WORK/out")"
fi
unset EXTRA

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

[ "$rc" -eq 0 ] || exit 1
if [ "$scenarios" -lt 47 ]; then
  printf 'FAIL: only %d scenarios ran; the suite has been narrowed\n' "$scenarios" >&2
  exit 1
fi
printf 'release-step bite-check OK (%d scenarios)\n' "$scenarios"
