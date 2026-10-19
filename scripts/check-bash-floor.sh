#!/bin/sh
# Usage: scripts/check-bash-floor.sh
# Runs the script-driven task targets of the committed HEAD under bash 3.2,
# the bash macOS ships; CI's bash 5 accepts constructs 3.2 aborts on.
set -eu

IMAGE="docker.io/library/bash:3.2@sha256:0fd7cb8499c63a3c9345e7088a9cd83bb69f6e895e83833859aff838a0312091"
MISE_VERSION="2026.10.3"
TARGETS="gitops:validate tofu:ci knowledge:validate bootstrap:check-render supply-chain:check-release-step supply-chain:oci-allowlist"

if [ "${1:-}" != "--inside" ]; then
  engine="$(command -v docker || command -v podman)" || {
    echo "ERROR: check-bash-floor needs docker or podman" >&2
    exit 2
  }
  exec "$engine" run --rm -e GITHUB_TOKEN -v "$(pwd):/src:ro" "$IMAGE" sh /src/scripts/check-bash-floor.sh --inside
fi

case "$(uname -m)" in
  x86_64) arch=x64 sum=eb956895c3620ed3d753b2da3c15ea179f892c8980fa8875ba6096f585b844f8 ;;
  aarch64) arch=arm64 sum=1b849098a23ca0b7ec2733bddf243e9d29507779bba4e0e1101eec3c518bc542 ;;
  *) echo "ERROR: check-bash-floor: unsupported architecture $(uname -m)" >&2; exit 2 ;;
esac

# perl-utils provides shasum, which macOS and Ubuntu both ship and busybox lacks.
apk add --no-cache curl git python3 gettext perl-utils >/dev/null
curl -fsSLo /usr/local/bin/mise \
  "https://github.com/jdx/mise/releases/download/v${MISE_VERSION}/mise-v${MISE_VERSION}-linux-${arch}-musl"
echo "${sum}  /usr/local/bin/mise" | sha256sum -c - >/dev/null
chmod +x /usr/local/bin/mise

git config --global --add safe.directory /src
git clone -q /src /w
cd /w
# node has no official musl build; no target run here needs it.
export MISE_YES=1 MISE_TRUSTED_CONFIG_PATHS=/w MISE_DISABLE_TOOLS=node
mise install >/tmp/mise-install.log 2>&1 || { cat /tmp/mise-install.log; exit 1; }

version="$(bash -c 'echo "$BASH_VERSION"')"
case "$version" in
  3.2.*) echo "check-bash-floor: bash $version" ;;
  *) echo "ERROR: check-bash-floor: expected bash 3.2, got $version" >&2; exit 2 ;;
esac
rc=0
for t in $TARGETS; do
  if mise x -- task "$t" >/tmp/task.log 2>&1; then
    echo "ok    $t"
  else
    rc=1
    echo "FAIL  $t"
    sed 's/^/      /' /tmp/task.log
  fi
done
exit "$rc"
