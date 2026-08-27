#!/usr/bin/env python3
"""params.yaml ships the defaults, so it has to stay in step with them.

Fails if it names a param that does not exist, or gives a value that differs
from the pipeline default. A params.yaml key that is not a real param is a
silent no-op: the operator edits it, nothing changes, and the run quietly does
something other than what they asked for.

`ref` is exempt: it has no default and must be set.
"""
import re
import sys

import yaml

EXEMPT = {"ref"}

def defaults():
    out = {}
    for path in ("nextflow.config", "main.nf"):
        with open(path) as fh:
            for m in re.finditer(r"^params\.(\w+)\s*=\s*(.+?)\s*(?://.*)?$", fh.read(), re.M):
                out.setdefault(m.group(1), m.group(2).strip().strip('"'))
    return out

def main():
    declared = defaults()
    with open("params.yaml") as fh:
        given = yaml.safe_load(fh) or {}

    problems = []
    for key, value in given.items():
        if key not in declared:
            problems.append(f"{key}: not a pipeline param")
        elif key in EXEMPT:
            continue
        elif value is None:
            continue
        elif str(value).lower() != str(declared[key]).lower():
            problems.append(f"{key}: params.yaml has {value!r}, default is {declared[key]!r}")

    if problems:
        print("params.yaml is out of step with the pipeline defaults:")
        for p in problems:
            print("  " + p)
        return 1

    print(f"params.yaml OK ({len(given)} params, in step with the defaults)")
    return 0

if __name__ == "__main__":
    sys.exit(main())
