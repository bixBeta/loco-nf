#!/bin/bash
# Render the loco-pipe report. Follows the sartools pattern: bring the template
# into the task directory, render it there, then remove it so only the html is
# published.
#
# The figures are COPIED in rather than referenced where they lie. Quarto's
# embed-resources inlines everything into a single self contained html, and it
# will not follow paths outside the project directory to do it.
set -euo pipefail

# Quarto keeps a cache under \$XDG_CACHE_HOME, defaulting to \$HOME/.cache, and
# \$HOME is read-only inside the container on this cluster:
#   Read-only file system (os error 30): mkdir '/home/<user>/.cache/quarto'
# The same applies to any renderer that assumes a writable home, so keep both
# task-local, exactly as the analysis task does.
export HOME="\$PWD"
export XDG_CACHE_HOME="\$PWD/.cache"
export XDG_DATA_HOME="\$PWD/.local/share"
mkdir -p "\$XDG_CACHE_HOME" "\$XDG_DATA_HOME"

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

# lostruct writes separated.pca as a PDF, and it is the only figure the report
# expects that loco-pipe does not emit as a png. [0] takes the first page, so
# the output is <name>.png rather than <name>-0.png. Failures are reported
# rather than swallowed: silently skipping left the report saying the module had
# not run, which was misleading.
find figures -name '*.pdf' | while read -r p ; do
    out="\${p%.pdf}.png"
    if convert -density 150 "\${p}[0]" "\$out" 2>&1 ; then
        echo "converted \$p -> \$out"
    else
        echo "WARNING: could not convert \$p; the report will list it as missing" >&2
    fi
done

quarto render report.qmd \
    -P title:${id} \
    -P outdir:${outdir} \
    -o ${id}-loco-report.html

rm -f report.qmd
