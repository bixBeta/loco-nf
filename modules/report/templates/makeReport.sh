#!/bin/bash
# Render the loco-pipe report. Follows the sartools pattern: bring the template
# into the task directory, render it there, then remove it so only the html is
# published.
#
# The figures are COPIED in rather than referenced where they lie. Quarto's
# embed-resources inlines everything into a single self contained html, and it
# will not follow paths outside the project directory to do it.
set -euo pipefail

# the template is staged into this directory by nextflow; copy it under a
# different name so `rm` at the end cannot remove the staged input itself
cp -L ${qmd} report.qmd

mkdir -p figures docs

# -L follows symlinks, since publishDir and loco-pipe both leave plenty about.
# Missing pieces are not fatal: modules can be turned off in locopipe.yaml, and
# the report reports on whatever is actually there.
cp -rL ${outdir}/figures/. figures/ 2>/dev/null || true
cp -rL ${outdir}/docs/.    docs/    2>/dev/null || true
cp -L  ${outdir}/locopipe.yaml . 2>/dev/null || true
cp -L  ${outdir}/angsd/get_depth_global/depth_filter.tsv . 2>/dev/null || true

# lostruct writes one of its figures as a PDF. Convert it so it embeds like
# every other figure; ImageMagick and ghostscript are both in this image.
find figures -name '*.pdf' | while read -r p ; do
    convert -density 150 "\$p" "\${p%.pdf}.png" 2>/dev/null || true
done

quarto render report.qmd \
    -P title:${id} \
    -P outdir:${outdir} \
    -o ${id}-loco-report.html

rm -f report.qmd
