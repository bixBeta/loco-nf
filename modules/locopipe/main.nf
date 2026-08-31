// loco-pipe is driven through its own CLI inside the image, so this module is
// deliberately thin: it lets `loco-pipe init` lay out the project ( which is
// what keeps us in step with upstream ), then replaces only the two tables the
// operator actually controls, and hands off.
//
// Preparing and running are ONE process. Splitting them meant the second task
// reached the first task's directory through a staged symlink, which is what
// broke `..` resolution, the recorded scriptdir, and publishing. loco-pipe owns
// a single directory and works in place; the module now matches that.

threads      = params.threads

// --locopipebin points at a loco-pipe binary on the host; loco-pipe-local ships
// beside it, so the whole directory goes on PATH. Derived here rather than in
// nextflow.config, where file() is not available. Empty when running in the
// image, which already has both on PATH.
onPath       = params.locopipebin ? "export PATH=\"${file(params.locopipebin).parent}:\$PATH\"" : ""

// Snakemake writes a source cache under \$XDG_CACHE_HOME, which defaults to
// \$HOME/.cache, and \$HOME is frequently mounted read-only inside a container:
//
//   OSError: [Errno 30] Read-only file system: '/home/<user>/.cache'
//
// It fails at DAG construction, before any rule runs, so nothing is produced
// and snakemake still exits without a WorkflowError. Keeping HOME task-local
// removes the dependency on a writable home entirely.
TASK_HOME    = '''
export HOME="\$PWD"
export XDG_CACHE_HOME="\$PWD/.cache"
mkdir -p "\$XDG_CACHE_HOME"
'''.trim()


process LOCOPIPE {

    tag "$pin"

    // cpus / memory come from --threads and --mem, see nextflow.config

    // Only the small artefacts are published. The results themselves are
    // written straight into --outdir and never copied: they are large, and
    // moving them out of the directory snakemake tracks would break its resume.
    publishDir "pipeline_info", mode: "copy", overwrite: true, pattern: "versions.yml"
    publishDir "pipeline_info", mode: "copy", overwrite: true, pattern: "locopipe.log"

    input:
        val   pin
        val   samples
        val   contigs
        val   bams
        val   refpath
        val   outdir
        val   settings      // only to make an edited locopipe.yaml invalidate the cache
        val   overrides     // contents of --locoparams, likewise
        val   lococonfig    // contents of --lococonfig, a complete replacement
        path  ref
        path  fai
        path  mergescript

    output:
        path "versions.yml"  , emit: versions
        path "locopipe.log"  , emit: log, optional: true

    script:
    """
    ${onPath}
    ${TASK_HOME}

    task_dir=\$PWD

    cat > "\$task_dir/overrides.yaml" <<'LOCO_OVERRIDES'
${overrides}
LOCO_OVERRIDES

    cat > "\$task_dir/lococonfig.yaml" <<'LOCO_CONFIG'
${lococonfig}
LOCO_CONFIG

    # The six keys that are specific to this run rather than to the analysis.
    # Upstream ships them as /path/to/loco-pipe placeholders, and pop_level as
    # "species", which would not match the samples.tsv this front-end writes.
    cat > "\$task_dir/forced.yaml" <<'LOCO_FORCED'
global:
  basedir: ${outdir}
  reference: ${refpath}
  scriptdir: ${outdir}/workflow/scripts
  sample_table: samples.tsv
  pop_level: population
  chr_table: contigs.tsv
LOCO_FORCED

    # init is run from inside the project. It writes workflow/ into the current
    # directory and records scriptdir as an ABSOLUTE path to it in
    # locopipe.yaml, so laying it out anywhere else and moving it afterwards
    # leaves that path dangling:
    #   Fatal error: cannot open file '.../workflow/scripts/get_depth_filter.R'
    mkdir -p ${outdir}
    cd ${outdir}

    # Lay the project out ONCE. `loco-pipe init` opens locopipe.yaml with 'w',
    # so running it again discards whatever analysis settings were edited there
    # - which is precisely the file the operator is told to edit. Delete
    # locopipe.yaml, or the whole directory, to start over.
    #
    # init takes the bam files themselves ( not the reference ) as its
    # positional argument, and checks each one exists and is readable, which
    # also proves the container can see them. Its samples.tsv is overwritten
    # below, since init assigns every sample to a single group.
    if [ ! -f locopipe.yaml ] ; then
        loco-pipe init -o . -r ${refpath} ${bams} > "\$task_dir/init.log" 2>&1 || {
            cat "\$task_dir/init.log" ; exit 1 ; }
    else
        echo "reusing the project in ${outdir}; delete locopipe.yaml to start over"
    fi

    # A complete config supplied with --lococonfig replaces the generated one,
    # then the six run-specific keys are put back. Re-applied every run, so that
    # file stays the source of truth rather than drifting from what ran.
    if [ -s "\$task_dir/lococonfig.yaml" ] ; then
        cp "\$task_dir/lococonfig.yaml" locopipe.yaml
        echo "using the config supplied with --lococonfig"
        python3 "\$task_dir/${mergescript}" locopipe.yaml "\$task_dir/forced.yaml"
    fi

    # Apply --locoparams BEFORE loco-pipe runs, so the first run already uses the
    # intended settings rather than analysing with the defaults and being redone.
    # Re-applied every run, so that file is the record of what a run used; any
    # setting it does not name keeps whatever is in locopipe.yaml, including
    # hand edits. A setting that does not exist is an error, not a no-op.
    if [ -s "\$task_dir/overrides.yaml" ] ; then
        python3 "\$task_dir/${mergescript}" locopipe.yaml "\$task_dir/overrides.yaml"
    fi

    # The generated profile carries rerun-triggers: [mtime, params], so merely
    # rewriting a table makes snakemake redo everything downstream of it even
    # when the content is identical - which defeats the whole point of keeping
    # the project outside work/. Write only on a real change.
    write_if_changed() {
        tmp=\$(mktemp)
        cat > "\$tmp"
        if [ -f "\$1" ] && cmp -s "\$tmp" "\$1" ; then
            rm -f "\$tmp"
        else
            mv "\$tmp" "\$1"
            echo "updated \$1"
        fi
    }

    mkdir -p docs

    # the two tables the sheet actually determines
    write_if_changed docs/samples.tsv <<'SAMPLES_TSV'
${samples}
SAMPLES_TSV

    write_if_changed docs/contigs.tsv <<'CONTIGS_TSV'
${contigs}
CONTIGS_TSV

    # Snakemake would otherwise rebuild every conda env at run time and ignore
    # the image entirely. Idempotent: it rewrites workflow/config.yaml only
    # while the conda keys are still there.
    loco-pipe-local

    # terminator at column 0, like the two above. <<- strips leading TABS only,
    # so an indented terminator never matches and the heredoc swallows the rest
    # of the script.
    cat > "\$task_dir/versions.yml" <<END_VERSIONS
"${task.process}":
    loco-pipe: \$(loco-pipe --help > /dev/null 2>&1 && echo "0.1")
    snakemake: \$(snakemake --version)
    angsd: \$(angsd 2>&1 | grep -m1 -oE 'version: [^ ]+' | sed 's/version: //')
END_VERSIONS

    if [ "${params.launch}" != "true" ] ; then
        echo "prepared ${outdir} but did not launch it ( --launch false )"
        exit 0
    fi

    # -@ matches what Nextflow reserved, so snakemake cannot oversubscribe the
    # allocation it was given. Run from inside the project so it finds workflow/.
    log=\$task_dir/locopipe.log
    loco-pipe start -@ ${task.cpus} . 2>&1 | tee "\$log"

    # `loco-pipe start` calls subprocess.run without checking the return code,
    # so it exits 0 even when the workflow failed. Its log is the only reliable
    # signal, and without this a failed run looks like a successful one.
    if grep -qE 'WorkflowError|command exited with non-zero|MissingInputException|Error in rule|^Error' "\$log" ; then
        echo "loco-pipe reported a failure, see pipeline_info/locopipe.log" >&2
        tail -40 "\$log" >&2
        exit 1
    fi

    # A run that does nothing at all is a failure too: snakemake can exit
    # cleanly with an empty DAG, and loco-pipe start returns 0 either way, so
    # without this the pipeline reports success having produced no results.
    if [ ! -d figures ] ; then
        echo "loco-pipe produced no figures directory - it did no work." >&2
        echo "Its log follows:" >&2
        tail -40 "\$log" >&2
        exit 1
    fi
    """

    stub:
    """
    mkdir -p ${outdir}/docs ${outdir}/figures ${outdir}/workflow
    printf '%s\\n' "${samples}" > ${outdir}/docs/samples.tsv
    printf '%s\\n' "${contigs}" > ${outdir}/docs/contigs.tsv
    touch ${outdir}/locopipe.yaml
    touch versions.yml
    echo "stub" > locopipe.log
    """
}
