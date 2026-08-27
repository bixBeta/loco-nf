# loco-pipe, all dependencies in one image.
#
# ohana is only published for linux-64, so this image is x86_64 only. Build it
# from the repository root:
#
#   docker build --platform linux/amd64 -f containers/Dockerfile -t loco-pipe .
#
# Then convert to Singularity/Apptainer (see containers/README.md).
FROM condaforge/miniforge3@sha256:609d8012d8ad3ea46c8e531ce2de9e727031960067b3a1e412c6e2954ef551c9

LABEL org.opencontainers.image.title="loco-pipe" \
      org.opencontainers.image.description="Snakemake pipeline for low-coverage whole-genome sequencing, with all tool and R dependencies baked in" \
      org.opencontainers.image.source="https://github.com/pdimens/loco-pipe"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# procps (ps) is used by Snakemake for resource accounting; the rest are
# needed by the workflow's shell blocks and by devtools' GitHub downloads.
RUN apt-get update && \
    apt-get install -y --no-install-recommends procps ca-certificates curl gzip tar && \
    rm -rf /var/lib/apt/lists/*

ENV CONDA_DIR=/opt/conda
COPY containers/envs/ /tmp/envs/

# One env per tool stack, mirroring the workflow's conda envs. Kept separate so
# that R 4.2, Snakemake's Python 3.11 and pcangsd's Python cannot conflict.
RUN conda env create -n angsd    -f /tmp/envs/angsd.yaml    && conda clean -afy
RUN conda env create -n pcangsd  -f /tmp/envs/pcangsd.yaml  && conda clean -afy
RUN conda env create -n ohana    -f /tmp/envs/ohana.yaml    && conda clean -afy
RUN conda env create -n locopipe -f /tmp/envs/locopipe.yaml && conda clean -afy
RUN conda env create -n r        -f /tmp/envs/r.yaml        && conda clean -afy

# lostruct is not on conda; the pipeline README pins this exact commit.
# Fetched from codeload rather than via devtools::install_github, which goes
# through api.github.com and fails against its unauthenticated rate limit.
# lostruct is pure R (no src/), so R CMD INSTALL needs no compiler.
ARG LOSTRUCT_REF=93ad59309151e44d2d3d0d7748cdc92f6121f564
RUN curl -sSL --retry 5 --retry-delay 3 \
      -o /tmp/lostruct.tar.gz \
      "https://codeload.github.com/petrelharp/local_pca/tar.gz/$LOSTRUCT_REF" && \
    mkdir -p /tmp/lostruct-src && \
    tar xzf /tmp/lostruct.tar.gz -C /tmp/lostruct-src --strip-components=1 && \
    "$CONDA_DIR/envs/r/bin/R" CMD INSTALL \
      --library="$CONDA_DIR/envs/r/lib/R/library" /tmp/lostruct-src/lostruct && \
    rm -rf /tmp/lostruct.tar.gz /tmp/lostruct-src && \
    "$CONDA_DIR/envs/r/bin/Rscript" --vanilla -e "library(lostruct); cat('lostruct OK\n')"

# The loco-pipe CLI and the workflow files it copies out on `loco-pipe init`.
COPY . /opt/loco-pipe-src
# --no-deps because conda already installed every runtime dependency, and
# because pyproject.toml's `graphviz>=14.1.2` is unsatisfiable from PyPI: that
# is the system Graphviz version, while PyPI's `graphviz` bindings stop at 0.21.
# The locopipe CLI never imports graphviz - Snakemake only needs the `dot`
# binary, which the conda graphviz package provides.
#
# The toyfish example dataset stays at /opt/loco-pipe-src/toyfish so the image
# can be smoke-tested without any external data.
RUN "$CONDA_DIR/envs/locopipe/bin/pip" install --no-cache-dir --no-deps /opt/loco-pipe-src

# Order matters. locopipe first so that `python` is Snakemake's interpreter
# rather than the one r-essentials drags in; ohana last since nothing else
# provides `convert` or `qpas`.
ENV PATH=/opt/conda/envs/locopipe/bin:/opt/conda/envs/r/bin:/opt/conda/envs/angsd/bin:/opt/conda/envs/pcangsd/bin:/opt/conda/envs/ohana/bin:/opt/conda/bin:/usr/local/bin:/usr/bin:/bin

# Keep R and Snakemake from writing into a read-only image or a stray $HOME.
ENV R_LIBS_USER=/tmp/R-libs \
    LC_ALL=C.UTF-8 \
    LANG=C.UTF-8 \
    PYTHONDONTWRITEBYTECODE=1

COPY containers/loco-pipe-check /usr/local/bin/loco-pipe-check
COPY containers/loco-pipe-local /usr/local/bin/loco-pipe-local
RUN chmod +x /usr/local/bin/loco-pipe-check /usr/local/bin/loco-pipe-local

CMD ["loco-pipe", "--help"]
