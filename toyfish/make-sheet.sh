#!/usr/bin/env bash
# Build a loco-nf sample sheet from the bundled toyfish dataset.
#
#   bash toyfish/make-sheet.sh [output.csv]
#
# The shipped toyfish/docs/sample_table.tsv carries "/path/to/loco-pipe"
# placeholders, so it cannot be used as-is; this writes the same samples with
# absolute paths and the columns loco-nf expects.
#
# Samples are grouped by the "species" column ( sunset / vermilion ), which is
# what upstream's config used. The "population" column splits vermilion three
# ways as well, if you would rather exercise more groups.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$PWD
OUT=${1:-$ROOT/toyfish-sheet.csv}
GROUP=${GROUP:-species}

TABLE=toyfish/docs/sample_table.tsv
[ -f "$TABLE" ] || { echo "no $TABLE - are you in the loco-nf repo?" >&2; exit 1; }

python3 - "$TABLE" "$OUT" "$ROOT" "$GROUP" <<'PY'
import csv, os, sys
table, out, root, group = sys.argv[1:5]
rows = list(csv.DictReader(open(table), delimiter="\t"))
if group not in rows[0]:
    sys.exit(f"no '{group}' column in the sample table; found {list(rows[0])}")
with open(out, "w", newline="") as fh:
    w = csv.writer(fh)
    w.writerow(["sample", "bam", "group"])
    for r in rows:
        # the shipped paths are placeholders, so rebuild them from the bam name
        bam = os.path.join(root, "toyfish", "bams", os.path.basename(r["bam"]))
        if not os.path.exists(bam):
            sys.exit(f"missing bam: {bam}")
        w.writerow([r["sample_name"], bam, r[group]])
print(f"{out}: {len(rows)} samples, grouped by '{group}'")
PY

# angsd refuses to run when the .fai is not strictly newer than the fasta, and
# a clone or an rsync easily lands both in the same second.
sleep 1
touch "$ROOT/toyfish/reference/toy_refgen.fa.fai"
echo "touched toyfish/reference/toy_refgen.fa.fai"
