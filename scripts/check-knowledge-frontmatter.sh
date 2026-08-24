#!/usr/bin/env bash
# Frontmatter gate for the knowledge/ OKF bundle.
#
# Asserts the six things `openknowledge validate` does not, each of which the
# bundle conventions (knowledge/rules/talos-base-bundle.md) state normatively
# and none of which any rule enforces:
#
#   - `sources[].resource` resolves, is repo-relative, and does not escape.
#   - `decided`, `generated.at` and `verified[].at` are quoted ISO 8601
#     datetimes and not in the future.
#   - a concept listing `sources` carries `generated`.
#   - no frontmatter carries the retired `timestamp` key.
#   - knowledge/index.md declares `okf_version`.
#   - a decision concept carries `decided` and neither `generated`,
#     `verified` nor `sources`.
#
# Bite-checked by scripts/check-knowledge-frontmatter.test.sh.
set -euo pipefail

# `resource` values are repo-relative, so resolve them from the repo root rather
# than from wherever the caller happens to stand.
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bundle="${1:-knowledge}"
[ -d "$bundle" ] || { echo "FAIL: '$bundle' is not a directory"; exit 1; }

python3 - "$bundle" <<'PY'
import os, re, sys, datetime

bundle = sys.argv[1]
DATE = re.compile(r'^"(\d{4})-(\d{2})-(\d{2})T\d{2}:\d{2}:\d{2}Z"$')
TODAY = datetime.date.today()
fails, stale = [], []


def frontmatter(path):
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().split("\n")
    if not lines or lines[0] != "---":
        return None
    try:
        return lines[1:lines.index("---", 1)]
    except ValueError:
        return None


def check_date(rel, key, raw):
    m = DATE.match(raw)
    if not m:
        fails.append(f"{rel}: {key} is not a quoted ISO 8601 datetime: {raw}")
        return None
    try:
        d = datetime.date(*(int(g) for g in m.groups()))
    except ValueError:
        fails.append(f"{rel}: {key} is not a real date: {raw}")
        return None
    if d > TODAY:
        fails.append(f"{rel}: {key} is in the future: {raw}")
    return d


seen_index = False
for dirpath, _, names in os.walk(bundle):
    for name in sorted(names):
        if not name.endswith(".md"):
            continue
        path = os.path.join(dirpath, name)
        rel = os.path.relpath(path, bundle)
        fm = frontmatter(path)
        if fm is None:
            continue

        if rel == "index.md":
            seen_index = True
            if '"0.2"' not in "\n".join(l for l in fm if l.startswith("okf_version:")):
                fails.append("index.md: okf_version must be declared as \"0.2\" "
                             "(okf-version compares it to --spec and reports nothing when it is absent)")

        keys = {l.split(":", 1)[0] for l in fm if re.match(r"^[A-Za-z_][A-Za-z0-9_-]*:", l)}
        is_decision = any(l.strip() == "type: decision" for l in fm)
        template = rel == "decisions/template.md"

        if "timestamp" in keys:
            fails.append(f"{rel}: 'timestamp' is retired — use generated.at, verified[].at or decided")

        gen = ver = None
        in_sources = False
        for line in fm:
            if line == "sources:":
                in_sources = True
                continue
            if in_sources:
                if re.match(r"^[A-Za-z_][A-Za-z0-9_-]*:", line):
                    in_sources = False
                elif line.lstrip().startswith("#") or not line.strip():
                    continue
                else:
                    m = re.match(r"^  - resource: (\S.*)$", line)
                    if not m:
                        fails.append(f"{rel}: sources entry is not '- resource: <path>': {line.strip()}")
                        continue
                    p = m.group(1).strip()
                    if p.startswith("/") or ".." in p.split("/"):
                        fails.append(f"{rel}: resource must be repo-relative and inside the repo: {p}")
                    elif not os.path.exists(p):
                        fails.append(f"{rel}: resource does not exist: {p}")
                    continue
            m = re.match(r"^generated: \{ by: (\S+), at: (\S+) \}$", line)
            if m:
                gen = check_date(rel, "generated.at", m.group(2))
                continue
            m = re.match(r"^  - \{ by: (\S+), at: (\S+) \}$", line)
            if m:
                d = check_date(rel, "verified[].at", m.group(2))
                if d and (ver is None or d > ver):
                    ver = d
                continue
            m = re.match(r"^decided: (\S+)$", line)
            if m:
                check_date(rel, "decided", m.group(1))

        if is_decision:
            if not template and "decided" not in keys:
                fails.append(f"{rel}: a decision concept must carry 'decided'")
            for forbidden in ("generated", "verified", "sources"):
                if forbidden in keys:
                    fails.append(f"{rel}: a decision concept must not carry '{forbidden}' "
                                 f"(knowledge/decisions/index.md §Status vocabulary)")
        elif "sources" in keys and "generated" not in keys:
            fails.append(f"{rel}: lists 'sources' but carries no 'generated' — "
                         "v0.2 makes the field optional, so the concept would claim nothing")

        if gen and ver and ver < gen:
            stale.append(f"{rel} (verified {ver}, content changed {gen})")

if not seen_index:
    fails.append("index.md: the bundle root index was not found")

for f in fails:
    print(f"FAIL: {f}")
if fails:
    sys.exit(1)

if stale:
    print(f"NOTE: {len(stale)} concept(s) carry an honest verification that predates their "
          "content change. Not a failure — the record stands, but the reading is not current:")
    for s in stale:
        print(f"      {s}")
print(f"OK: knowledge/ frontmatter is v0.2-conformant ({len(stale)} not-current verification(s)).")
PY
