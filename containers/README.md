# A single Singularity image for loco-pipe

This directory builds one Apptainer/Singularity image containing every binary
and R package loco-pipe shells out to, so the pipeline runs without Snakemake
building conda environments at run time.

## What's inside

| Component | Version | Provides |
|---|---|---|
| angsd | 0.940 | `angsd`, `realSFS`, `thetaStat` |
| samtools | 1.16.1 | `samtools index` |
| pcangsd | 1.36.4 | `pcangsd` |
| ohana | 0.1 | `convert` (bgl2lgm), `qpas` |
| Snakemake | ≥9.0 | workflow engine |
| loco-pipe | 0.1 | `loco-pipe init` / `loco-pipe start` |
| R | 4.2 | tidyverse 2.0.0, cowplot 1.1.1, fitdistrplus 1.1-8, extraDistr 1.9.1, Matrix 1.5-3, survival 3.5-3, data.table 1.15.4, RSpectra 0.16-1, MASS, stringi, devtools, MKL |
| lostruct | commit `93ad593` | local PCA (`library(lostruct)`) |

Versions come from the pipeline's own `locopipe/workflow/envs/*.yaml`. The
`r.yaml` and `lostruct.yaml` environments are merged into one R installation
(they pin identical R/tidyverse/cowplot versions), as are `angsd.yaml` and
`samtools.yaml`. Everything else gets its own conda env inside the image so
that R 4.2, Snakemake's Python and pcangsd's Python cannot conflict; all their
`bin` directories are on `PATH`.

**The image is x86_64 only.** ohana is published for `linux-64` only, so there
is no aarch64 build. On an Apple Silicon Mac it builds under emulation and runs
on any x86_64 cluster.

## Building

### On a cluster that has Apptainer (preferred)

```bash
apptainer build --fakeroot loco-pipe.sif containers/loco-pipe.def
```

Run it from the repository root — the definition copies the loco-pipe source
into the image.

### Via Docker, then convert

Use this when the build host has Docker but no Apptainer. From the repository
root:

```bash
docker build --platform linux/amd64 -f containers/Dockerfile -t loco-pipe:latest .
```

```bash
docker save loco-pipe:latest -o loco-pipe-docker.tar
```

Copy `loco-pipe-docker.tar` to the cluster and convert it there:

```bash
apptainer build loco-pipe.sif docker-archive://loco-pipe-docker.tar
```

That conversion needs no root or `--fakeroot`.

## Verifying the image

```bash
apptainer exec loco-pipe.sif loco-pipe-check
```

It resolves every binary the workflow calls and loads every R package the
scripts use, and exits non-zero if anything is missing. The definition file
runs it automatically in its `%test` section at the end of a build.

The image was validated by running the bundled toyfish dataset end to end:
all 104 jobs completed with no errors and reproduced the full reference figure
set in `toyfish/figures` (19 plots), exercising angsd, realSFS, thetaStat,
samtools, pcangsd, ohana, lostruct and every R plotting script.

## Running the pipeline

Snakemake still defaults to building conda environments, because
`loco-pipe init` writes `software-deployment-method: conda` into the profile it
generates. Since the image already has all of it, turn that off once after
`init` with the bundled helper:

```bash
apptainer exec loco-pipe.sif loco-pipe-local
```

Full sequence, using the bundled toy dataset:

```bash
apptainer exec loco-pipe.sif loco-pipe init -o toytest -r /opt/loco-pipe-src/toyfish/reference/toy_refgen.fa /opt/loco-pipe-src/toyfish/bams/
```

```bash
apptainer exec loco-pipe.sif loco-pipe-local
```

```bash
apptainer exec loco-pipe.sif loco-pipe start -@ 8 toytest
```

Edit `toytest/docs/samples.tsv` between `init` and `start` to assign real group
names — `init` puts every sample in a single group named `groupname` and says
so in its notice.

### Binding your data

Apptainer auto-mounts `$HOME` and the current directory, but nothing else. The
`bam` column of `samples.tsv` holds absolute paths, so if your data or
reference genome live anywhere else, bind those paths explicitly:

```bash
apptainer exec --bind /scratch/mydata,/refs loco-pipe.sif loco-pipe start -@ 16 myproject
```

### On SLURM

The simplest approach is to request one allocation and let Snakemake
parallelize within it, rather than having it submit per-rule jobs:

```bash
srun --cpus-per-task=32 --mem=120G --time=24:00:00 \
  apptainer exec --bind /scratch loco-pipe.sif loco-pipe start -@ 32 myproject
```

To use the workflow's own SLURM profile instead
(`locopipe/workflow/profiles/slurm`), Snakemake must run on the login node
outside the container and each submitted job must re-enter it, which means
setting the profile's job wrapper to `apptainer exec /path/to/loco-pipe.sif`.
The single-allocation form above avoids that entirely and is what these
instructions assume.

## Upstream quirks worth knowing

These are properties of loco-pipe itself, not of the image.

- **`loco-pipe start` always exits 0.** It calls `subprocess.run` without
  checking the return code, so a failed Snakemake run still reports success to
  your shell or job scheduler. Check the Snakemake log, or grep the output for
  `WorkflowError`, rather than trusting `$?`.
- **`pyproject.toml`'s `graphviz>=14.1.2` is unsatisfiable from PyPI.** That is
  the system Graphviz version; the PyPI `graphviz` bindings stop at 0.21. Plain
  `pip install .` therefore fails. The image installs the CLI with `--no-deps`
  and gets real Graphviz (and its `dot` binary) from conda.
- **The lostruct rules name a conda env rather than a file.**
  `run_lostruct_global.smk` uses `conda: "lostruct_lcpipe"`, which only resolves
  if you built an env by that name beforehand — hence the manual lostruct steps
  in the main README. The image sidesteps this by putting lostruct on `PATH`.
- **Your reference `.fai` must be strictly newer than the `.fa`.** angsd
  refuses to run with *"fai index file ... looks older than corresponding
  fastafile"*, and equal mtimes count as older — which is easy to hit after a
  `git clone`, a tarball extraction, or an `rsync` that lands both files in the
  same second. Fix it with `touch /path/to/reference.fa.fai`; that is all
  `toyfish/prepare.sh` does. This bites the toy dataset in particular.

## Notes

- ohana's `convert` is unrelated to ImageMagick's `convert`. Do not add
  ImageMagick to this image — it would shadow the binary `run_ohana.smk` calls.
  `loco-pipe-check` asserts that `convert` still resolves to ohana's.
- `R_LIBS_USER` is set to `/tmp/R-libs` so R never tries to write into the
  read-only image or pick up stray packages from your host `~/R` library.
- The toyfish example dataset ships at `/opt/loco-pipe-src/toyfish` so the
  image can be smoke-tested without any external data.
- Sizes: ~6.2 GB as a Docker image, ~1.5 GB as a SIF.
