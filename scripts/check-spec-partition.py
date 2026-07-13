#!/usr/bin/env python3
"""B2 partition assert: exclusivity + completeness of spec source ownership.

Exit 0 iff (a) every primary source path is owned by exactly one spec,
(b) every file in the enumerated substrate source universe has a primary
owner, (c) every spec dir is kebab-case.
"""
import glob
import os
import re
import subprocess
import sys

REPO = sys.argv[1] if len(sys.argv) > 1 else "."
os.chdir(REPO)

def frontmatter(path):
    text = open(path, encoding="utf-8").read()
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    return m.group(1) if m else ""

def primary_sources(fm):
    """Parse the sources.primary list (also accepts a bare sources: list)."""
    out, in_sources, in_primary, in_secondary = [], False, False, False
    for line in fm.splitlines():
        if re.match(r"^sources:", line):
            in_sources, in_primary, in_secondary = True, False, False
            continue
        if re.match(r"^\S", line):  # next top-level key
            in_sources = False
            continue
        if not in_sources:
            continue
        if re.match(r"^\s+primary:", line):
            in_primary, in_secondary = True, False
            continue
        if re.match(r"^\s+secondary:", line):
            in_primary, in_secondary = False, True
            continue
        m = re.match(r"^\s+-\s+(.+?)\s*$", line)
        if m and not in_secondary:
            out.append(m.group(1).split("#")[0].strip())  # strip fragments
    return [p for p in out if p]

def tracked(globpat):
    r = subprocess.run(["git", "ls-files", globpat], capture_output=True, text=True)
    return [l for l in r.stdout.splitlines() if l]

# --- enumerated substrate source universe -----------------------------------
universe = set()
universe |= {f for f in tracked("tofu/modules/talos-cluster/*.tf")}
universe |= {f for f in tracked("tofu/modules/talos-cluster/helm/*.yaml")}
universe |= {f for f in tracked("tofu/modules/talos-cluster/manifests/*.yaml")}
universe |= {f for f in tracked("kubernetes/**") if not f.endswith(".gitkeep")}
universe |= {f for f in tracked("schemas/*.json")}
universe |= {"platform-hardware-features.yaml"}
universe |= {f for f in tracked("policies/**/*.rego")}
universe |= {".github/workflows/oci-publish.yml",
             ".ci-oci-tarball-include.txt", ".ci-oci-tarball-expected.txt"}
# QA-class exclusions inside otherwise-covered trees (documented in ADR-0015):
universe -= {f for f in universe if "/examples/" in f or "/tests/" in f or "/test/" in f}
# Markdown is documentation, never an enforcing/behavioral source.
universe -= {f for f in universe if f.endswith(".md")}

owners = {}   # source path -> [spec ids]
specs = sorted(glob.glob("openspec/specs/*/spec.md"))
fail = 0
for spec in specs:
    sid = spec.split("/")[2]
    if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", sid):
        print(f"FAIL kebab-case: {sid}")
        fail = 1
    for src in primary_sources(frontmatter(spec)):
        owners.setdefault(src, []).append(sid)

for src, sids in sorted(owners.items()):
    if len(sids) > 1:
        print(f"FAIL exclusivity: {src} owned by {sids}")
        fail = 1
    if not (os.path.exists(src) or src.startswith("Taskfile.yml")):
        print(f"FAIL dangling source: {src} (owner {sids[0]})")
        fail = 1

unowned = sorted(universe - set(owners))
for src in unowned:
    print(f"FAIL completeness: {src} has no primary owner")
    fail = 1

print(f"specs={len(specs)} owned_paths={len(owners)} universe={len(universe)} -> {'FAIL' if fail else 'OK'}")
sys.exit(fail)
