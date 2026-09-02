#!/bin/sh
# Download a public Helm chart into the caller's .terraform cache and accept it
# only when its SHA-256 matches the digest pinned by this module.
set -eu

if [ "$#" -ne 3 ]; then
  echo "fetch-verified-chart: expected URL, SHA-256 and destination path" >&2
  exit 2
fi

url="$1"
expected="$2"
destination="$3"

case "$expected" in
  *[!0-9a-f]*|'')
    echo "fetch-verified-chart: expected SHA-256 must be 64 lowercase hexadecimal characters" >&2
    exit 2
    ;;
esac
[ "${#expected}" -eq 64 ] || {
  echo "fetch-verified-chart: expected SHA-256 must be 64 lowercase hexadecimal characters" >&2
  exit 2
}

command -v curl >/dev/null 2>&1 || {
  echo "fetch-verified-chart: curl is required to download $url" >&2
  exit 2
}

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo "fetch-verified-chart: sha256sum or shasum is required" >&2
    exit 2
  fi
}

verify() {
  actual="$(sha256 "$1")"
  [ "$actual" = "$expected" ] || {
    echo "fetch-verified-chart: SHA-256 mismatch for $url: expected $expected, got $actual" >&2
    exit 1
  }
}

mkdir -p "$(dirname "$destination")"

if [ -f "$destination" ]; then
  verify "$destination"
else
  temporary="${destination}.tmp.$$"
  trap 'rm -f "$temporary"' EXIT HUP INT TERM
  curl -fsSL --retry 3 -o "$temporary" "$url"
  verify "$temporary"
  mv "$temporary" "$destination"
  trap - EXIT HUP INT TERM
fi

# hashicorp/external requires a JSON object whose values are strings.
printf '%s\n' '{"verified":"true"}'
