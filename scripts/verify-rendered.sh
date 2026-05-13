#!/usr/bin/env bash
# verify-rendered.sh — re-render every component with chart.lock.yaml
# into a tmpdir and diff against the committed _rendered/ tree.
#
# Used by CI to enforce that committed _rendered/ output matches what
# render-component.sh produces from current chart.lock.yaml + values.yaml
# + _rendered-overlay/ inputs. Drift fails the build.
#
# Exit codes:
#   0 — all components match committed _rendered/
#   1 — at least one component drifts
#   2 — render failed for at least one component

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
INFRA_DIR="${ROOT}/kubernetes/base/infrastructure"

# GNU find -printf is not portable to macOS; use -exec dirname instead.
components="$(find "${INFRA_DIR}" -mindepth 2 -maxdepth 2 -name chart.lock.yaml -exec dirname {} \; \
  | xargs -n1 basename | sort)"

if [ -z "${components}" ]; then
  echo "no components with chart.lock.yaml found — nothing to verify"
  exit 0
fi

drift=0
render_fail=0
tmproot="$(mktemp -d)"
trap 'rm -rf "${tmproot}"' EXIT

for comp in ${components}; do
  echo "==> verify ${comp}"
  comp_dir="${INFRA_DIR}/${comp}"
  rendered_dir="${comp_dir}/_rendered"
  if [ ! -d "${rendered_dir}" ]; then
    echo "  MISSING:  ${rendered_dir} (run \`make render-component COMPONENT=${comp}\`)"
    drift=1
    continue
  fi

  # Snapshot committed render.
  snapshot="${tmproot}/${comp}.committed"
  cp -r "${rendered_dir}" "${snapshot}"

  # Re-render in place; render-component.sh writes to _rendered/.
  if ! "${ROOT}/scripts/render-component.sh" "${comp}" >/dev/null 2>"${tmproot}/${comp}.err"; then
    echo "  RENDER FAILED for ${comp}:"
    sed 's/^/    /' < "${tmproot}/${comp}.err" >&2
    render_fail=1
    continue
  fi

  if ! diff -ruN "${snapshot}" "${rendered_dir}" > "${tmproot}/${comp}.diff"; then
    echo "  DRIFT in ${comp}:"
    sed 's/^/    /' < "${tmproot}/${comp}.diff" | head -50
    if [ "$(wc -l < "${tmproot}/${comp}.diff")" -gt 50 ]; then
      echo "    ... (diff truncated; see ${tmproot}/${comp}.diff for full output)"
    fi
    drift=1
  else
    echo "  OK"
  fi
done

if [ "${render_fail}" -ne 0 ]; then
  echo ""
  echo "::error::one or more components failed to render"
  exit 2
fi
if [ "${drift}" -ne 0 ]; then
  echo ""
  echo "::error::committed _rendered/ tree drifts from chart.lock.yaml + values.yaml + _rendered-overlay/"
  echo "Re-run \`make render-all\` and commit the result, or fix chart.lock.yaml / values.yaml."
  exit 1
fi

echo ""
echo "All components: rendered output matches committed."
