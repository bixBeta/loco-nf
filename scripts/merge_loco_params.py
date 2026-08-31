#!/usr/bin/env python3
"""Apply a small YAML of overrides to a generated locopipe.yaml, in place.

    merge_loco_params.py locopipe.yaml overrides.yaml

Why not load and re-dump with pyyaml: locopipe.yaml is heavily commented, and
those comments are the documentation the operator reads when deciding what to
change. A round-trip through pyyaml would delete every one of them. So this
edits the value on the matching line and leaves the rest of the file alone.

An override naming a section or setting that does not exist is an error, not a
no-op. A silently ignored setting is the worst outcome here: the run looks
configured and is not.
"""
import re
import sys

import yaml


def known_settings(config_path):
    """section -> set(settings), read from the generated config."""
    try:
        cfg = yaml.safe_load(open(config_path)) or {}
    except Exception:
        return {}
    return {s: set(v) for s, v in cfg.items() if isinstance(v, dict)}


def load_overrides(path, known):
    with open(path) as fh:
        data = yaml.safe_load(fh) or {}
    if not isinstance(data, dict):
        sys.exit(f"{path}: expected a mapping of sections, got {type(data).__name__}")

    # Report everything wrong at once: the file is edited by uncommenting, and
    # fixing one problem per run is a poor way to spend a cluster.
    problems = []
    for section, settings in data.items():
        if isinstance(settings, dict):
            continue
        # By far the likeliest mistake: uncommenting a setting but leaving its
        # section header commented, which lifts it to the top level.
        holders = sorted(s for s, keys in known.items() if section in keys)
        if holders:
            problems.append(
                f"  '{section}' is a setting, not a section - its section header is "
                f"probably still commented out.\n"
                f"      '{section}' belongs to: {', '.join(holders)}\n"
                f"      Uncomment the section header as well, so it reads:\n"
                f"          {holders[0]}:\n            {section}: {settings}"
            )
        else:
            problems.append(
                f"  '{section}' must be a mapping of settings, got "
                f"{type(settings).__name__}"
            )
    if problems:
        sys.exit(
            f"{path}:\n" + "\n".join(problems)
            + "\n\n  An override names a section and then the settings under it:\n"
              "      subset_snp_list_global:\n        n: 400"
        )
    return data


def render(value, quoted):
    """Keep the quoting style of the line being replaced.

    upstream writes some numerics as strings ( minmaf: "0.05", pval: "1e-6" )
    because the rules interpolate them straight into shell commands. Dropping
    the quotes can change how yaml parses them - 1e-6 is a string in YAML 1.1,
    not a float - so the original style is preserved rather than guessed at.
    """
    text = "true" if value is True else "false" if value is False else str(value)
    return f'"{text}"' if quoted else text


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    config_path, overrides_path = sys.argv[1], sys.argv[2]

    known = known_settings(config_path)
    overrides = load_overrides(overrides_path, known)
    if not overrides:
        print("no overrides given")
        return 0

    with open(config_path) as fh:
        lines = fh.readlines()

    # section -> setting -> value, tracking which ones we managed to apply
    pending = {s: dict(v) for s, v in overrides.items()}
    applied, section = [], None

    for i, line in enumerate(lines):
        top = re.match(r"^([A-Za-z_][\w]*):\s*$", line)
        if top:
            section = top.group(1)
            continue
        if section not in pending:
            continue
        m = re.match(r"^(\s+)([A-Za-z_][\w]*):(\s*)(.*?)(\s*)$", line)
        if not m:
            continue
        indent, key, gap, old, trail = m.groups()
        if key not in pending[section]:
            continue

        # keep any trailing comment on the line
        comment = ""
        body = old
        if "#" in old:
            body, comment = old.split("#", 1)
            comment = " #" + comment
            body = body.rstrip()

        new = render(pending[section].pop(key), body.startswith('"'))
        if body != new:
            lines[i] = f"{indent}{key}:{gap}{new}{comment}\n"
            applied.append(f"{section}.{key}: {body} -> {new}")
        else:
            applied.append(f"{section}.{key}: already {new}")
        if not pending[section]:
            del pending[section]

    if pending:
        missing = []
        for sec, ks in pending.items():
            for k in ks:
                if sec not in known:
                    near = [s for s in known if sec in s or s in sec]
                    hint = f"  ( no such section{'; did you mean ' + near[0] + '?' if near else ''} )"
                    missing.append(f"{sec}.{k}{hint}")
                else:
                    missing.append(f"{sec}.{k}  ( no such setting in {sec} )")
        sys.exit(
            "these overrides do not exist in " + config_path + ":\n  "
            + "\n  ".join(missing)
            + "\n\nCheck the spelling against that file. An override that names "
              "nothing would leave the run silently unconfigured, so this is an "
              "error rather than a warning."
        )

    with open(config_path, "w") as fh:
        fh.writelines(lines)

    for line in applied:
        print("  " + line)
    print(f"applied {len(applied)} override(s) to {config_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
