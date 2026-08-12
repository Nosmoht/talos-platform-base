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
EVERY commit in the range that CONTRIBUTED to the violating file carries
the trailer. The trailer is an auditable, reviewable claim — the PR
reviewer judges it.

Contribution is what decides a merge commit's place in that set, not the
fact that git lists it. A merge whose content for the file equals what a
mechanical 3-way merge of its parents yields introduced nothing to certify
and is skipped. This is load-bearing rather than cosmetic: branch protection
here requires up-to-date branches, so a base-sync merge is FORCED on every
PR, and git lists it for every file both sides touched — counting it would
void an otherwise valid escape and leave history rewriting as the only
remedy. A merge that INVENTED content (hand-resolved conflict, evil merge)
stays in the set and must carry the trailer itself. Residual: when every
listed commit for a violating file is such a skipped merge, nothing is left
to attribute the change to and the violation fails closed. That state is not
known to be reachable — a probe could not construct it, because a merge whose
result matches the base side is TREESAME to it and then the file is absent
from the diff as well — so the branch is a backstop, not a live risk.

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
    """Run git. `ok_codes=None` tolerates ANY exit code — for probes whose
    failure is a meaningful answer (unsupported subcommand, absent path)
    rather than a broken environment."""
    r = subprocess.run(["git", *args], capture_output=True, text=True)
    if ok_codes is not None and r.returncode not in ok_codes:
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


def merge_shas(base):
    """Merge commit shas in base..HEAD."""
    _, out = git("rev-list", "--merges", f"{base}..HEAD")
    return set(out.split())


def tree_entry(rev, path):
    """`<mode> <type> <oid>` for `path` at `rev` (commit or tree); None if absent.

    Mode and type are part of the identity, not just the object id. A merge that
    flips the executable bit, or turns the path into a symlink (120000) or a
    gitlink (160000), recorded something its parents did not supply even though
    the blob id can be unchanged — and this is not academic here: two spec-owned
    primary sources (scripts/lint-cluster-yaml.sh, scripts/lint-hardware-features.sh)
    are invoked by CI with no interpreter prefix, so their mode IS behavior.
    Comparing the blob id alone let such a merge pass as a non-contributor.
    """
    rc, out = git("ls-tree", "--full-tree", rev, "--", path, ok_codes=None)
    if rc != 0 or not out.strip():
        return None
    fields = out.split("\t", 1)[0].split()
    return " ".join(fields[:3]) if len(fields) >= 3 else None


def merge_invented_content(sha, path):
    """True when merge `sha`'s `path` is not what a mechanical merge yields.

    Re-runs git's own merge machinery over the two parents (`merge-tree
    --write-tree`, git >= 2.38) and compares the resulting tree entry — mode,
    type AND object id — against the one the merge actually recorded. Equal means
    the merge only replayed what the 3-way merge produces unaided — nothing of
    its own to certify. Everything
    else counts as a contribution, so the probe fails CLOSED: a hand-resolved
    conflict (the mechanical merge exits non-zero), an evil merge, an octopus
    merge, or a git too old for `--write-tree`.

    Deliberately NOT `diff-tree --cc` emptiness, the obvious cheaper test:
    `--cc` compresses per HUNK, so a clean auto-merge of two edits close enough
    to share a hunk still prints hunks and would be misread as an invention.
    Scenario B of scripts/check-staleness-gate-bite.sh exists to hold that line.

    `--write-tree` deposits loose objects in the local object store; they are
    unreferenced and `git gc` collects them.

    Disclosed assumption: "mechanical" means git's DEFAULT merge machinery. The
    repo ships no `.gitattributes`, so nothing currently redirects a path to a
    custom `merge=` driver. Adding one on a spec-owned `primary` source would
    make this comparison depend on whether that driver is defined where the check
    runs, which is not established either way — re-validate before doing so.
    """
    _, out = git("rev-list", "--parents", "-n", "1", sha)
    parents = out.split()[1:]
    if len(parents) != 2:
        return True
    rc, tree_out = git("merge-tree", "--write-tree", *parents, ok_codes=None)
    if rc != 0 or not tree_out.strip():
        return True
    tree = tree_out.splitlines()[0].strip()
    return tree_entry(tree, path) != tree_entry(sha, path)


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
    merges = merge_shas(args.base)
    fail = 0
    for f, spec in violations:
        _, log_out = git("log", "--no-renames", "--format=%H",
                         f"{args.base}..HEAD", "--", f)
        # Only commits that CONTRIBUTED content for this file can certify it.
        # A merge that merely replayed its parents' variants is dropped —
        # branch protection forces a base-sync merge on every PR, so counting
        # it would void the escape for any file both sides touched. A merge
        # that invented content is kept and must carry the trailer itself.
        contributing = [sha for sha in log_out.split()
                        if sha not in merges or merge_invented_content(sha, f)]
        # Escaped only when every contributing commit carries the trailer
        # (per-commit scope; an unrelated commit's trailer never suppresses
        # another commit's violation). An empty set means the change is
        # uncommitted, or attributable only to dropped merges — fail closed
        # either way, since there is no claim to judge.
        if contributing and all(sha in escaped_shas for sha in contributing):
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
