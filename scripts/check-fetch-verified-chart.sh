#!/usr/bin/env bash
# Regression test for fetch-verified-chart.sh. Uses only local file:// fixtures,
# so the blocking tofu:ci path stays offline.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
fetcher="${repo_root}/tofu/modules/talos-cluster/scripts/fetch-verified-chart.sh"

[ -x "$fetcher" ] || {
  echo "::error::check-fetch-verified-chart: executable missing: ${fetcher#"${repo_root}/"}" >&2
  exit 1
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

printf '%s' 'known chart bytes' > "$work/source.tgz"
expected="$(sha256sum "$work/source.tgz" | awk '{print $1}')"

result="$($fetcher "file://$work/source.tgz" "$expected" "$work/cache/chart.tgz")"
[ "$result" = '{"verified":"true"}' ] || {
  echo "::error::check-fetch-verified-chart: unexpected success result: $result" >&2
  exit 1
}
cmp -s "$work/source.tgz" "$work/cache/chart.tgz" || {
  echo "::error::check-fetch-verified-chart: verified download differs from source" >&2
  exit 1
}

printf '%s' 'changed chart bytes' > "$work/changed.tgz"
if "$fetcher" "file://$work/changed.tgz" "$expected" "$work/cache/changed.tgz" >"$work/out" 2>"$work/err"; then
  echo "::error::check-fetch-verified-chart: a digest mismatch was accepted" >&2
  exit 1
fi
grep -q 'SHA-256 mismatch' "$work/err" || {
  echo "::error::check-fetch-verified-chart: mismatch failure did not name SHA-256" >&2
  exit 1
}

printf '%s' 'tampered cache' > "$work/cache/chart.tgz"
if "$fetcher" "file://$work/source.tgz" "$expected" "$work/cache/chart.tgz" >"$work/out" 2>"$work/err"; then
  echo "::error::check-fetch-verified-chart: a tampered cached chart was accepted" >&2
  exit 1
fi
grep -q 'SHA-256 mismatch' "$work/err" || {
  echo "::error::check-fetch-verified-chart: cached mismatch did not name SHA-256" >&2
  exit 1
}

echo "check-fetch-verified-chart: OK — valid chart accepted; changed download and tampered cache rejected"
