#!/usr/bin/env python3
"""check-cilium-reference-values.py — closes the #211 defect class.

`kubernetes/bootstrap/cilium/values.yaml` is reference-only (the seed renders
from `tofu/modules/talos-cluster/helm/cilium-values.yaml`), but it ships in the
OCI artifact and is what a consumer is told to copy into a Day-2 self-managed
Application. Helm does not run `--strict`, so a value spelling the pinned chart
has REMOVED is dropped silently: the consumer's cluster is misconfigured with no
error at render or apply time. That is exactly what happened to
`encryption.strictMode.{enabled,cidr,allowRemoteNodeIdentities}` when Cilium 1.20
removed the flat form.

This validates every key path in that file against the pinned chart's own
`values.schema.json`, and fails on a path the chart does not declare.

Deliberately NOT a hard failure when the chart cannot be fetched. The repo
already decided that a chart-registry outage must not block unrelated merges
(`tofu-validate.yml` marks its chart-pulling job advisory for that reason), so an
unreachable registry SKIPS loudly and exits 0. A value the chart rejects FAILS.
The trade-off is stated rather than hidden: during an outage a bad value can
merge.

Exit codes: 0 = pass or skip, 1 = unrecognized value path, 2 = internal error.
"""

from __future__ import annotations

import json
import subprocess
import sys
import tarfile
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

REFERENCE_VALUES = Path("kubernetes/bootstrap/cilium/values.yaml")
VARIABLES_TF = Path("tofu/modules/talos-cluster/variables.tf")


def repo_root() -> Path:
    out = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True, text=True, check=True,
    )
    return Path(out.stdout.strip())


def pinned_chart_version(variables_tf: Path) -> str:
    """Read the single source of truth for the pinned chart version.

    Since #210 the version literal exists in exactly one place — the
    `cilium_chart_version` variable's default — so this parse cannot drift from
    what the module actually renders.
    """
    text = variables_tf.read_text()
    marker = 'variable "cilium_chart_version"'
    start = text.find(marker)
    if start == -1:
        sys.exit(f"FAIL: {variables_tf} declares no cilium_chart_version variable")
    block = text[start : text.find("\nvariable ", start + 1)]
    for line in block.splitlines():
        stripped = line.strip()
        if stripped.startswith("default") and "=" in stripped:
            return stripped.split("=", 1)[1].strip().strip('"')
    sys.exit(f"FAIL: cilium_chart_version in {variables_tf} has no default to read")


def fetch_values_schema(version: str) -> dict | None:
    """Return the pinned chart's values.schema.json, or None if unreachable."""
    url = f"https://helm.cilium.io/cilium-{version}.tgz"
    try:
        with urllib.request.urlopen(url, timeout=30) as response:  # noqa: S310 - pinned https host
            payload = response.read()
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        print(f"SKIP: could not fetch {url} ({exc}) — registry unreachable, not a value error")
        return None

    with tempfile.TemporaryDirectory() as tmp:
        archive = Path(tmp) / "chart.tgz"
        archive.write_bytes(payload)
        try:
            with tarfile.open(archive) as tar:
                member = tar.extractfile("cilium/values.schema.json")
                if member is None:
                    print(f"SKIP: chart {version} ships no values.schema.json — nothing to validate against")
                    return None
                return json.loads(member.read())
        except (tarfile.TarError, KeyError, json.JSONDecodeError) as exc:
            print(f"SKIP: chart {version} archive or schema unreadable ({exc})")
            return None


def load_yaml(path: Path) -> dict:
    """Parse YAML via the repo's pinned `yq`, not PyYAML.

    Deliberate: the CI job already installs a pinned `yq`, while PyYAML is not a
    declared dependency anywhere in this repo. Depending on it would make the gate
    skip silently on a runner without it — a gate that can vacuously pass is worse
    than no gate. A missing `yq` is a setup bug, so it exits non-zero and loud
    rather than skipping.
    """
    try:
        out = subprocess.run(
            ["yq", "-o=json", "-N", ".", str(path)],
            capture_output=True, text=True, check=True,
        )
    except FileNotFoundError:
        print("FAIL: yq not on PATH — required to parse the reference values", file=sys.stderr)
        raise SystemExit(2) from None
    except subprocess.CalledProcessError as exc:
        print(f"FAIL: yq could not parse {path}: {exc.stderr.strip()}", file=sys.stderr)
        raise SystemExit(2) from None
    return json.loads(out.stdout) or {}


def branches(node: dict) -> list[dict]:
    """Flatten a schema node's union branches so a key declared in any one counts."""
    out = [node]
    for keyword in ("oneOf", "anyOf", "allOf"):
        for sub in node.get(keyword, []):
            if isinstance(sub, dict):
                out.extend(branches(sub))
    return out


def declares(node: dict, key: str) -> dict | None:
    """Return the sub-schema for `key`, or None if the node forbids/omits it.

    A node with no `properties` in any branch is treated as free-form: the value
    is accepted and its subtree is not descended. This is the conservative
    direction — it under-reports rather than inventing a typo.
    """
    saw_properties = False
    for branch in branches(node):
        props = branch.get("properties")
        if isinstance(props, dict):
            saw_properties = True
            if key in props:
                return props[key] if isinstance(props[key], dict) else {}
        extra = branch.get("additionalProperties")
        if extra is True or isinstance(extra, dict):
            return extra if isinstance(extra, dict) else {}
    return None if saw_properties else {}


def walk(value: object, schema: dict, path: tuple[str, ...], bad: list[str]) -> None:
    if not isinstance(value, dict):
        return
    for key, child in value.items():
        here = (*path, str(key))
        sub = declares(schema, str(key))
        if sub is None:
            bad.append(".".join(here))
            continue
        walk(child, sub, here, bad)


def main() -> int:
    root = repo_root()
    reference = root / REFERENCE_VALUES
    if not reference.is_file():
        sys.exit(f"FAIL: {REFERENCE_VALUES} missing")

    version = pinned_chart_version(root / VARIABLES_TF)
    schema = fetch_values_schema(version)
    if schema is None:
        print(f"SKIP: {REFERENCE_VALUES} not validated against chart {version}")
        return 0

    values = load_yaml(reference)
    bad: list[str] = []
    walk(values, schema, (), bad)

    if bad:
        print(
            f"FAIL: {REFERENCE_VALUES} sets {len(bad)} value path(s) that chart {version} "
            "does not declare. Helm merges without --strict, so each is DROPPED silently — "
            "a consumer copying this file gets a cluster that is not configured the way the "
            "file says. Fix the spelling against the pinned chart or remove the key:",
            file=sys.stderr,
        )
        for entry in bad:
            print(f"  - {entry}", file=sys.stderr)
        return 1

    print(f"OK: every value path in {REFERENCE_VALUES} is declared by chart {version}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
