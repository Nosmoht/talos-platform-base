#!/usr/bin/env python3
"""Spec staleness gate (ADR-0015 staleness convention, CI-enforced).

A diff that touches a spec's `primary` source must also touch the owning
spec — otherwise the spec silently drifts from the behavior it describes.
Renames are surfaced as delete+add (`--no-renames`), so a renamed primary
source still fires against its owning spec.

Fragment-keyed sources (e.g. `Taskfile.yml#bootstrap:argocd`) are matched
at FRAGMENT granularity: the violation fires only when the diff touches
lines inside the named YAML-key block (resolved at HEAD by indentation),
so an unrelated edit elsewhere in the file does not force a spec touch —
whole-file coupling would train reviewers to rubber-stamp the escape
trailer. Fail-closed: an unresolvable fragment (renamed/removed key,
deleted file) counts as touched. Disclosed residuals of the block model:
behavior reachable from OUTSIDE the owned blocks (top-level `vars:`/
`env:` edits, YAML anchors) does not fire — own every block the behavior
lives in (e.g. a task AND its deps target); and a non-blank line indented
at or above the key's level inside a block (unusual for this Taskfile)
truncates the resolved range early.

Escape hatch for diffs that verifiably do not change described behavior
(comment-only edits, refactors): the commit trailer line
`Spec-Impact: none` — matched in the commit BODY only (never the subject)
and scoped PER COMMIT: a violation is downgraded to a warning only when
EVERY commit in the range that touched the violating file carries the
trailer. The trailer is an auditable, reviewable claim — the PR reviewer
judges it.

Usage: check-spec-staleness.py --base <ref>   (e.g. origin/main)

Exit codes: 0 clean/escaped · 1 stale spec(s) · 2 environment error.
"""
import argparse
import glob
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from spec_lib import frontmatter, normalize, primary_sources  # noqa: E402

TRAILER = "Spec-Impact: none"


def git(*args, ok_codes=(0,)):
    r = subprocess.run(["git", *args], capture_output=True, text=True)
    if r.returncode not in ok_codes:
        print(f"ERROR: git {' '.join(args)}: {r.stderr.strip()}", file=sys.stderr)
        sys.exit(2)
    return r.returncode, r.stdout


def trailer_commits(base):
    """Commit shas in base..HEAD whose message BODY carries the trailer."""
    _, out = git("log", "-z", f"{base}..HEAD", "--format=%H%n%B")
    shas = set()
    for entry in out.split("\0"):
        if not entry.strip():
            continue
        sha, _, message = entry.partition("\n")
        body_lines = message.splitlines()[1:]  # skip the subject line
        if any(line.strip() == TRAILER for line in body_lines):
            shas.add(sha)
    return shas


def fragment_range(head_lines, frag):
    """1-based (start, end) of the YAML-key block `frag:` at HEAD, by
    indentation; None when the key is not found (caller fails closed).
    The key must END after the colon (`(?:\\s|$)`) so a colon-superset key
    (`bootstrap:argocd:precheck:`) can never shadow `bootstrap:argocd:`."""
    pat = re.compile(r"^(\s*)" + re.escape(frag) + r":(?:\s|$)")
    for i, line in enumerate(head_lines):
        m = pat.match(line)
        if not m:
            continue
        indent = len(m.group(1))
        end = len(head_lines)
        for j in range(i + 1, len(head_lines)):
            s = head_lines[j]
            if s.strip() and (len(s) - len(s.lstrip())) <= indent:
                end = j
                break
        return (i + 1, end)
    return None


def changed_head_ranges(base, path):
    """HEAD-side line ranges the diff touches (pure deletions count as the
    two adjacent HEAD lines, conservatively)."""
    _, out = git("diff", "--unified=0", "--no-renames",
                 f"{base}...HEAD", "--", path)
    ranges = []
    for m in re.finditer(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@", out, re.M):
        start = int(m.group(1))
        count = int(m.group(2)) if m.group(2) is not None else 1
        if count == 0:  # pure deletion between HEAD lines start and start+1
            ranges.append((max(start, 1), start + 1))
        else:
            ranges.append((start, start + count - 1))
    return ranges


def fragment_touched(base, path, frags):
    """True iff the diff touches any of the owned fragment blocks (or the
    situation is unresolvable — fail closed)."""
    rc, out = git("show", f"HEAD:{path}", ok_codes=(0, 128))
    if rc != 0:
        return True  # file gone at HEAD — fail closed
    head_lines = out.splitlines()
    changed = changed_head_ranges(base, path)
    for frag in sorted(frags):
        block = fragment_range(head_lines, frag)
        if block is None:
            return True  # fragment key not found — fail closed
        if any(a <= block[1] and b >= block[0] for a, b in changed):
            return True
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True,
                    help="ref to diff against (merge-base semantics), e.g. origin/main")
    args = ap.parse_args()

    _, diff_out = git("diff", "--name-only", "--no-renames",
                      f"{args.base}...HEAD")
    changed = {normalize(l) for l in diff_out.splitlines() if l}
    if not changed:
        print("OK: empty diff — nothing to check")
        return 0

    # file part -> {spec path -> set of fragments (None = whole file)}
    owners = {}
    for spec in sorted(glob.glob("openspec/specs/*/spec.md")):
        for src in primary_sources(frontmatter(spec)):
            file_part, sep, frag = src.partition("#")
            key = normalize(file_part)
            owners.setdefault(key, {}).setdefault(normalize(spec), set()).add(
                frag if sep else None)

    violations = []
    for f in sorted(changed):
        for spec, frags in sorted(owners.get(f, {}).items()):
            if spec in changed:
                continue
            if None not in frags and not fragment_touched(args.base, f, frags):
                print(f"INFO: {f} changed outside the fragment(s) owned by "
                      f"{spec} ({', '.join(sorted(frags))}) — not stale")
                continue
            violations.append((f, spec))

    if not violations:
        print(f"OK: {len(changed)} changed file(s), no owning spec left untouched")
        return 0

    escaped_shas = trailer_commits(args.base)
    fail = 0
    for f, spec in violations:
        _, log_out = git("log", "--no-renames", "--format=%H",
                         f"{args.base}..HEAD", "--", f)
        touching = log_out.split()
        # Escaped only when every commit touching THIS file carries the
        # trailer (per-commit scope; an unrelated commit's trailer never
        # suppresses another commit's violation). No touching commit means
        # the change is uncommitted — never escapable.
        if touching and all(sha in escaped_shas for sha in touching):
            print(f"WARN stale spec (escaped per-commit via '{TRAILER}'): "
                  f"{f} changed but owning {spec} did not — reviewer judges "
                  f"the no-behavior-change claim")
        else:
            print(f"FAIL stale spec: {f} changed but owning {spec} did not")
            fail = 1

    if fail:
        print(f"Update the owning spec (or, for verified no-behavior-change "
              f"diffs, add a '{TRAILER}' trailer to the BODY of every commit "
              f"touching the file).")
    return fail


if __name__ == "__main__":
    sys.exit(main())
