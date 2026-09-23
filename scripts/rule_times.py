#!/usr/bin/env python3
"""Per-rule timings from snakemake's own logs.

    rule_times.py <outdir>/.snakemake/log/*.snakemake.log

loco-pipe's rules carry no benchmark: directive, so there is nothing that
records how long anything took. But snakemake stamps a time before each job it
starts and again when it finishes one, and names the rule both times, which is
enough to recover the profile after the fact - including for runs that have
already happened.

Pass several logs to profile a run that was resumed across restarts.

Two totals are reported because they answer different questions:

  wall     the sum of each job's duration. With jobs running concurrently this
           exceeds the elapsed time of the run, so read it as "how much work",
           not "how long you waited".
  longest  the slowest single job of that rule, which is what actually bounds
           the run when the rule is the last thing left.
"""
import collections
import datetime
import re
import sys

TS = re.compile(r"^\[(\w{3} \w{3} +\d+ +\d+:\d+:\d+ \d{4})\]\s*$")
RULE = re.compile(r"^\s*(?:local|check)?rule (\w+):")
JOBID = re.compile(r"^\s*jobid: (\d+)")
DONE = re.compile(r"^Finished jobid: (\d+)")


def parse(paths):
    # jobid -> (rule, started); a resumed run reuses jobids across logs, so the
    # start is consumed when its finish is seen rather than kept forever.
    started, durations = {}, collections.defaultdict(list)
    now, pending = None, None

    for path in paths:
        with open(path, errors="replace") as fh:
            for line in fh:
                line = line.rstrip("\n")

                m = TS.match(line)
                if m:
                    stamp = " ".join(m.group(1).split())
                    try:
                        now = datetime.datetime.strptime(stamp, "%a %b %d %H:%M:%S %Y")
                    except ValueError:
                        now = None
                    continue

                m = RULE.match(line)
                if m:
                    pending = (m.group(1), now)
                    continue

                m = JOBID.match(line)
                if m and pending:
                    started[m.group(1)] = pending
                    pending = None
                    continue

                m = DONE.match(line)
                if m:
                    job = started.pop(m.group(1), None)
                    if job and job[1] and now:
                        durations[job[0]].append((now - job[1]).total_seconds())

    return durations, started


def hms(seconds):
    return str(datetime.timedelta(seconds=int(seconds)))


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)

    durations, unfinished = parse(sys.argv[1:])
    if not durations:
        sys.exit("no completed jobs found - are these snakemake logs?")

    rows = sorted(durations.items(), key=lambda kv: sum(kv[1]), reverse=True)
    width = max(len(r) for r, _ in rows)
    total = sum(sum(v) for v in durations.values())

    print(f"{'rule':<{width}}  {'jobs':>5}  {'wall':>10}  {'longest':>10}  {'share':>6}")
    print("-" * (width + 38))
    for rule, secs in rows:
        print(
            f"{rule:<{width}}  {len(secs):>5}  {hms(sum(secs)):>10}  "
            f"{hms(max(secs)):>10}  {100 * sum(secs) / total:>5.1f}%"
        )
    print("-" * (width + 38))
    print(f"{'':<{width}}  {sum(len(v) for v in durations.values()):>5}  {hms(total):>10}")

    if unfinished:
        # a job that started and never finished is the interesting one when a
        # run was killed or is still going
        print()
        print("started but never finished:")
        for job, (rule, when) in sorted(unfinished.items(), key=lambda kv: kv[1][0]):
            print(f"  {rule}  ( jobid {job}, started {when} )")


if __name__ == "__main__":
    main()
