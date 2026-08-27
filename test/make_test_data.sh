#!/usr/bin/env bash
# Build the minimal inputs CI needs: a tiny indexed reference, some empty bams,
# a sample sheet pointing at them, and a bin/ holding the fake loco-pipe CLI.
#
# Nothing here is real data. The point is to exercise the front-end's own logic
# ( sheet parsing, contig selection, table generation ), not the population
# genomics, which lives in loco-pipe and is tested by its own toy dataset.
set -euo pipefail

cd "$(dirname "$0")"

mkdir -p ref bams bin

# ---- reference --------------------------------------------------------------
# Three contigs straddling the default --minlen of 1 Mb, so the default path is
# what gets exercised: chr_big and chr_mid are kept, chr_small is dropped.
# Sizing them below 1 Mb would make the auto contig list come out empty and
# every downstream assertion fail for the wrong reason.
#
# 4 MB of text, which the runner writes in well under a second. The .fai is
# written directly rather than with samtools, which CI does not have; the
# offsets below match the layout emitted here.
{
    echo ">chr_big"
    head -c 2000000 /dev/zero | tr '\0' 'A'
    echo
    echo ">chr_mid"
    head -c 1500000 /dev/zero | tr '\0' 'C'
    echo
    echo ">chr_small"
    head -c 500000 /dev/zero | tr '\0' 'G'
    echo
} > ref/ref.fa

# name, length, offset, linebases, linewidth
{
    printf 'chr_big\t2000000\t9\t2000000\t2000001\n'
    printf 'chr_mid\t1500000\t2000019\t1500000\t1500001\n'
    printf 'chr_small\t500000\t3500031\t500000\t500001\n'
} > ref/ref.fa.fai

# angsd treats an index with the same mtime as the fasta as stale, so make sure
# it is strictly newer here too - the pipeline warns about this for real data.
sleep 1
touch ref/ref.fa.fai

# ---- bams -------------------------------------------------------------------
for s in S1 S2 S3 S4 ; do
    : > "bams/${s}.bam"
    : > "bams/${s}.bam.bai"
done

# ---- sheets -----------------------------------------------------------------
{
    echo "sample,bam,group"
    echo "S1,$PWD/bams/S1.bam,alpha"
    echo "S2,$PWD/bams/S2.bam,alpha"
    echo "S3,$PWD/bams/S3.bam,beta"
    echo "S4,$PWD/bams/S4.bam,beta"
} > sample-sheet.csv

# every sample in one group: should warn, not fail
{
    echo "sample,bam,group"
    echo "S1,$PWD/bams/S1.bam,alpha"
    echo "S2,$PWD/bams/S2.bam,alpha"
} > sample-sheet-onegroup.csv

# a repeated sample name: loco-pipe takes one bam per sample, so this must fail
{
    echo "sample,bam,group"
    echo "S1,$PWD/bams/S1.bam,alpha"
    echo "S1,$PWD/bams/S2.bam,beta"
} > sample-sheet-dup.csv

# a bam that is not there
{
    echo "sample,bam,group"
    echo "S1,$PWD/bams/nope.bam,alpha"
} > sample-sheet-missingbam.csv

# missing the group column entirely
{
    echo "sample,bam"
    echo "S1,$PWD/bams/S1.bam"
} > sample-sheet-nogroup.csv

# ---- fake CLI ---------------------------------------------------------------
# both names live in one directory, since --locopipebin puts its parent on PATH
install -m 0755 fake-locopipe           bin/loco-pipe
install -m 0755 fake-loco-pipe-local    bin/loco-pipe-local

echo "test data ready in $PWD"
