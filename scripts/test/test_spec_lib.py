#!/usr/bin/env python3
"""Red-green binding for scripts/spec_lib.py (run by `task spec:validate`).

The flow-style parsing branches and the declares-primary detector have no
committed spec that exercises them (all specs use block style), so without
this test a revert of either would leave every gate green while the
staleness/partition machinery silently loses ownership coverage.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from spec_lib import declares_primary, primary_sources  # noqa: E402

BLOCK = "sources:\n  primary:\n    - a.tf\n    - b.tf\n  secondary:\n    - c.tf"
# Column-0 sequence: valid YAML puts bare-list items at the parent key's
# indent level — must parse, not be mistaken for a next top-level key.
COLUMN0 = "sources:\n- a.tf\n- b.tf\nreferences:\n- r.md"
FLOW_PRIMARY = "sources:\n  primary: [a.tf, 'b.tf']\n  secondary:\n    - c.tf"
FLOW_BARE = "sources: [a.tf, \"b.tf\"]"
SECONDARY_ONLY = "sources:\n  secondary:\n    - c.tf"
# Declared-but-unparseable styles: the parser yields nothing, so the
# partition gate must FAIL via declares_primary (never silently own nothing).
MULTILINE_FLOW = "sources:\n  primary: [\n    a.tf,\n  ]"
FLOW_MAP = "sources: {primary: [a.tf]}"
# Quoted key: not recognized as the primary key — its items are treated as
# an unknown nested key's content (never harvested), and declares_primary
# forces the partition gate to FAIL instead of silently owning nothing.
QUOTED_KEY = 'sources:\n  "primary":\n    - a.tf'
# Nested block scalar under sources: — its dash lines are prose, not
# sources (phantom-ownership guard).
NESTED_SCALAR = ("sources:\n  primary:\n    - a.tf\n  description: |\n"
                 "    - not/a/source.tf\n    - also/not.tf")

CASES = [
    ("block style parses", primary_sources(BLOCK) == ["a.tf", "b.tf"]),
    ("flow primary parses", primary_sources(FLOW_PRIMARY) == ["a.tf", "b.tf"]),
    ("bare flow sources parses", primary_sources(FLOW_BARE) == ["a.tf", "b.tf"]),
    ("column-0 sequence parses and stops at the next key",
     primary_sources(COLUMN0) == ["a.tf", "b.tf"]),
    ("secondary-only yields no primary", primary_sources(SECONDARY_ONLY) == []),
    ("secondary-only declares nothing", not declares_primary(SECONDARY_ONLY)),
    ("block style declares", declares_primary(BLOCK)),
    ("flow primary declares", declares_primary(FLOW_PRIMARY)),
    ("bare flow declares", declares_primary(FLOW_BARE)),
    # The guard condition of check-spec-partition.py: declared AND unparsed.
    ("multiline flow trips the guard",
     declares_primary(MULTILINE_FLOW) and primary_sources(MULTILINE_FLOW) == []),
    ("flow map trips the guard",
     declares_primary(FLOW_MAP) and primary_sources(FLOW_MAP) == []),
    ("quoted key trips the guard (declared, harvested as nothing)",
     declares_primary(QUOTED_KEY) and primary_sources(QUOTED_KEY) == []),
    ("nested block scalar never yields phantom sources",
     primary_sources(NESTED_SCALAR) == ["a.tf"]),
]

fail = 0
for name, ok in CASES:
    print(f"{'ok' if ok else 'FAIL'} - {name}")
    if not ok:
        fail = 1
sys.exit(fail)
