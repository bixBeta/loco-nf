#!/usr/bin/env python3
"""loco-params.yaml lists every loco-pipe setting, so it has to stay in step.

Fails if it names a setting that does not exist, or omits one that does. A stale
reference is worse than none: an operator uncommenting a setting that was
renamed upstream gets a failed run, and one that never appears here is a setting
nobody knows they can change.

The six the front-end owns are excluded on purpose - overriding them would
fight the pipeline.
"""
import re
import sys

import yaml

FRONTEND = {"basedir", "reference", "scriptdir", "sample_table", "pop_level", "chr_table"}


def upstream_settings():
    src = open("locopipe/workflow/__init__.py").read()
    tmpl = re.search(r'CONFIG\s*=\s*(""")(.*?)\1', src, re.S).group(2)
    cfg = yaml.safe_load(
        tmpl.format(basedir="/b", reference="/r", scriptdir="/s",
                    groupcol="population", sampletable="s.tsv", chromtable="c.tsv")
    )
    return {
        f"{section}.{key}"
        for section, settings in cfg.items()
        if isinstance(settings, dict)
        for key in settings
        if key not in FRONTEND
    }


def listed_settings():
    found, section = set(), None
    for line in open("loco-params.yaml"):
        m = re.match(r"^# ([A-Za-z_]\w*):$", line)
        if m:
            section = m.group(1)
            continue
        m = re.match(r"^#   ([A-Za-z_]\w*):", line)
        if m and section:
            found.add(f"{section}.{m.group(1)}")
    return found


def main():
    upstream, listed = upstream_settings(), listed_settings()
    problems = []
    for name in sorted(listed - upstream):
        problems.append(f"  {name}: listed here but not a loco-pipe setting")
    for name in sorted(upstream - listed):
        problems.append(f"  {name}: a loco-pipe setting that is not listed here")
    if problems:
        print("loco-params.yaml is out of step with loco-pipe's config:")
        print("\n".join(problems))
        return 1
    print(f"loco-params.yaml OK ({len(listed)} settings, matching loco-pipe)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
