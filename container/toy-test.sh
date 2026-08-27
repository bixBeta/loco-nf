#!/usr/bin/env bash
# Smoke-test a loco-pipe SIF by running the bundled toyfish dataset end to end.
# Everything it needs is inside the image; no other files required.
#
#   ./toy-test.sh /path/to/loco-pipe.sif [workdir] [threads]
#
# Expect ~20 min and 19 figures in <workdir>/toytest/figures.
set -euo pipefail

SIF=${1:?usage: toy-test.sh /path/to/loco-pipe.sif [workdir] [threads]}
WORK=${2:-$PWD/locopipe-toytest}
THREADS=${3:-8}

SIF=$(cd "$(dirname "$SIF")" && pwd)/$(basename "$SIF")
command -v apptainer >/dev/null && RUN=apptainer || RUN=singularity

mkdir -p "$WORK"
cd "$WORK"

echo "==> checking dependencies"
$RUN exec "$SIF" loco-pipe-check

echo "==> staging the toyfish dataset"
rm -rf toyfish toytest workflow
$RUN exec "$SIF" cp -r /opt/loco-pipe-src/toyfish "$WORK/toyfish"
chmod -R u+w toyfish
# angsd needs the .fai strictly newer than the .fa; equal mtimes count as older.
sleep 1 && touch toyfish/reference/toy_refgen.fa.fai

echo "==> initializing the project"
$RUN exec "$SIF" loco-pipe init -o toytest \
    -r "$WORK/toyfish/reference/toy_refgen.fa" "$WORK/toyfish/bams/"

echo "==> assigning the real sunset/vermilion groups"
$RUN exec "$SIF" python -c "
import csv
ref = {r['sample_name']: r['species'] for r in csv.DictReader(open('$WORK/toyfish/docs/sample_table.tsv'), delimiter='\t')}
rows = list(csv.DictReader(open('$WORK/toytest/docs/samples.tsv'), delimiter='\t'))
with open('$WORK/toytest/docs/samples.tsv', 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=['sample_name','bam','population'], delimiter='\t')
    w.writeheader()
    for r in rows:
        r['population'] = ref[r['sample_name']]
        w.writerow(r)
"

echo "==> using the container's tools instead of building conda envs"
$RUN exec "$SIF" loco-pipe-local

echo "==> running the pipeline"
# loco-pipe start always exits 0, even on failure, so check the output instead.
$RUN exec "$SIF" loco-pipe start -@ "$THREADS" toytest 2>&1 | tee run.log

echo
if grep -qE "WorkflowError|command exited with non-zero" run.log; then
    echo "FAILED - see $WORK/run.log" >&2
    exit 1
fi

n=$(find toytest/figures -type f \( -name '*.png' -o -name '*.pdf' \) | wc -l | tr -d ' ')
echo "produced $n figures in $WORK/toytest/figures (expected 19)"
[ "$n" -eq 19 ] && echo "TOY TEST PASSED" || { echo "unexpected figure count" >&2; exit 1; }
