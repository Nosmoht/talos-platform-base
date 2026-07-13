#!/usr/bin/env python3
"""Spec source-ownership partition assert (ADR-0015 ownership model).

Asserts over the ENUMERATED substrate source universe below:
  (a) exclusivity  — every primary source key is owned by exactly one spec;
  (b) completeness — every universe file has a primary owner. Completeness
      is relative to the enumeration: adding a NEW substrate source class
      (a second module, a new schema format/location, a new top-level
      source dir) requires extending the universe here in the same PR —
      the unknown-module guard below catches the most likely drift case.
  (c) spec ids are kebab-case.

Source keys keep any `#fragment` (e.g. `Taskfile.yml#bootstrap:argocd`),
so two specs owning DIFFERENT fragments of one file do not collide; the
existence check applies to the file part. Paths are normalized before
matching (leading `./`, trailing slashes, redundant separators).

Exit 0 iff all assertions hold.
"""
import glob
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from spec_lib import declares_primary, frontmatter, normalize, primary_sources  # noqa: E402

REPO = sys.argv[1] if len(sys.argv) > 1 else "."
os.chdir(REPO)

def tracked(globpat):
    r = subprocess.run(["git", "ls-files", globpat], capture_output=True,
                       text=True, check=True)
    return [normalize(l) for l in r.stdout.splitlines() if l]

# --- enumerated substrate source universe -----------------------------------
universe = set()
universe |= set(tracked("tofu/modules/talos-cluster/*.tf"))
universe |= set(tracked("tofu/modules/talos-cluster/helm/*.yaml"))
universe |= set(tracked("tofu/modules/talos-cluster/manifests/*.yaml"))
universe |= set(tracked("kubernetes/**"))
universe |= set(tracked("schemas/**"))
universe |= {"platform-hardware-features.yaml"}
universe |= set(tracked("policies/**/*.rego"))
universe |= {".github/workflows/oci-publish.yml",
             ".ci-oci-tarball-include.txt", ".ci-oci-tarball-expected.txt"}
# QA-class exclusions inside otherwise-covered trees (documented in ADR-0015):
universe -= {f for f in universe
             if "/examples/" in f or "/tests/" in f or "/test/" in f
             or "/fixtures/" in f}
# Markdown is documentation, never an enforcing/behavioral source.
universe -= {f for f in universe if f.endswith(".md")}

fail = 0

# Drift guard: a NEW module directory is a new source class the enumeration
# above does not cover — extend the universe in the same PR.
known_modules = {"talos-cluster"}
module_dirs = {p.split("/")[2] for p in tracked("tofu/modules/**")
               if p.count("/") >= 3}
for unknown in sorted(module_dirs - known_modules):
    print(f"FAIL universe drift: tofu/modules/{unknown}/ is not covered by "
          f"the enumerated universe — extend scripts/check-spec-partition.py")
    fail = 1

owners = {}   # source key (normalized, fragment kept) -> [spec ids]
specs = sorted(glob.glob("openspec/specs/*/spec.md"))
for spec in specs:
    sid = spec.split("/")[2]
    if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", sid):
        print(f"FAIL kebab-case: {sid}")
        fail = 1
    fm = frontmatter(spec)
    spec_sources = primary_sources(fm)
    # A declared primary list that parses to zero entries is a parser/
    # frontmatter defect — backstops any sources: style the parser cannot
    # read (the staleness gate would otherwise silently lose this spec's
    # ownership). Secondary-only specs (region views of a file owned
    # elsewhere) legitimately have no primary sources.
    if declares_primary(fm) and not spec_sources:
        print(f"FAIL primary sources declared but none parsed: {spec}")
        fail = 1
    for src in spec_sources:
        file_part, sep, frag = src.partition("#")
        key = normalize(file_part) + (sep + frag if sep else "")
        owners.setdefault(key, []).append(sid)

for key, sids in sorted(owners.items()):
    if len(sids) > 1:
        print(f"FAIL exclusivity: {key} owned by {sids}")
        fail = 1
    file_part = key.partition("#")[0]
    if not os.path.exists(file_part):
        print(f"FAIL dangling source: {key} (owner {sids[0]})")
        fail = 1

owned_files = {k.partition("#")[0] for k in owners}
unowned = sorted(universe - owned_files)
for src in unowned:
    print(f"FAIL completeness: {src} has no primary owner")
    fail = 1

print(f"specs={len(specs)} owned_keys={len(owners)} universe={len(universe)}"
      f" -> {'FAIL' if fail else 'OK'}")
sys.exit(fail)
