"""Shared helpers for the openspec source-ownership scripts.

Used by scripts/check-spec-partition.py (exclusivity + completeness) and
scripts/check-spec-staleness.py (primary-source diff → owning spec).
Parsing contract: spec frontmatter `sources:` with `primary:`/`secondary:`
sub-lists (a bare `sources:` list counts as primary); source keys may carry
a `#fragment` suffix distinguishing sections of one file.
"""
import posixpath
import re


def declares_primary(fm):
    """True when the frontmatter declares primary sources in ANY style.

    Deliberately broader than what primary_sources() can parse (quoted keys,
    flow maps, multi-line flow lists all match): the partition gate fails
    when this is True while primary_sources() is empty, so an unparseable
    declaration style surfaces as a hard error instead of silently dropping
    the spec out of the staleness gate. Secondary-only specs carry no
    'primary' token and stay valid.
    """
    return bool(re.search(r"primary|^sources:\s*[\[{]", fm, re.M))


def frontmatter(path):
    text = open(path, encoding="utf-8").read()
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    return m.group(1) if m else ""


def normalize(p):
    p = p.strip().rstrip("/")
    if p.startswith("./"):
        p = p[2:]
    return posixpath.normpath(p) if p else p


def primary_sources(fm):
    """Parse the sources.primary list (also accepts a bare sources: list).

    Handles both block style (`- item` lines) and flow style
    (`primary: [a, b]`) — a flow-style reformat must not silently yield an
    empty owner set (the staleness gate has no other backstop for sources
    outside the partition universe).
    """
    out, in_sources, in_secondary, in_other = [], False, False, False
    for line in fm.splitlines():
        if re.match(r"^sources:", line):
            in_sources, in_secondary, in_other = True, False, False
            m = re.match(r"^sources:\s*\[(.*)\]\s*$", line)
            if m:  # flow-style bare list on the same line
                out.extend(m.group(1).split(","))
                in_sources = False
            continue
        if re.match(r"^\S", line):
            # Column-0 sequence items still belong to a bare `sources:` list
            # (valid YAML puts them at the parent key's indent level).
            m = re.match(r"^-\s+(.+?)\s*$", line)
            if in_sources and not in_secondary and not in_other and m:
                out.append(m.group(1))
                continue
            in_sources = False  # next top-level key
            continue
        if not in_sources:
            continue
        if re.match(r"^\s+primary:", line):
            in_secondary, in_other = False, False
            m = re.match(r"^\s+primary:\s*\[(.*)\]\s*$", line)
            if m:  # flow-style primary list on the same line
                out.extend(m.group(1).split(","))
            continue
        if re.match(r"^\s+secondary:", line):
            in_secondary, in_other = True, False
            continue
        if re.match(r"^\s+[^-\s].*:", line):
            # Any OTHER nested key under sources: (a description block
            # scalar, an unknown sub-key) — its indented content must never
            # be harvested as source items (phantom-ownership guard).
            in_other = True
            continue
        m = re.match(r"^\s+-\s+(.+?)\s*$", line)
        if m and not in_secondary and not in_other:
            out.append(m.group(1))
    return [s for s in (x.strip().strip("'\"") for x in out) if s]
