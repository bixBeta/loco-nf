// loco-pipe is driven through its own CLI inside the image, so this module is
// deliberately thin: it lets `loco-pipe init` lay out the project ( which is
// what keeps us in step with upstream ), then replaces only the two tables the
// operator actually controls.

project      = params.project
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


process PREPARE_PROJECT {

    tag "$pin"

    label 'process_low'

    // Only published when stopping here. Otherwise LOCOPIPE_RUN writes into
    // this same directory and publishes the finished version; publishing both
    // would race for one name in the launch dir and leave the operator looking
    // at a copy taken before the analysis ran.
    publishDir "."            , mode: "copy", overwrite: true, enabled: !params.launch, pattern: "${params.project}"
    publishDir "pipeline_info", mode: "copy", overwrite: true, pattern: "versions.yml"

    input:
        val   pin
        val   samples
        val   contigs
        val   bams
        path  ref
        path  fai

    output:
        path "${project}"      , emit: project
        path "versions.yml"    , emit: versions

    script:
    """
    ${onPath}
    ${TASK_HOME}

    # init lays out docs/, locopipe.yaml and the workflow/ tree. It takes the bam
    # files themselves ( not the reference ) as its positional argument, and
    # checks each one exists and is readable, which also proves the container can
    # see them. Its samples.tsv is overwritten below, since init assigns every
    # sample to a single group.
    loco-pipe init -o ${project} -r ${ref} ${bams} > init.log 2>&1 || {
        cat init.log ; exit 1 ; }

    # the two tables the sheet actually determines
    cat > ${project}/docs/samples.tsv <<'SAMPLES_TSV'
${samples}
SAMPLES_TSV

    cat > ${project}/docs/contigs.tsv <<'CONTIGS_TSV'
${contigs}
CONTIGS_TSV

    # Snakemake would otherwise rebuild every conda env at run time and ignore
    # the image entirely.
    loco-pipe-local

    # init writes workflow/ next to the project, and `loco-pipe start` resolves
    # it relative to the launch dir, so it has to travel with the project
    mv workflow ${project}/workflow

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        loco-pipe: \$(loco-pipe --help > /dev/null 2>&1 && echo "0.1")
        snakemake: \$(snakemake --version)
        angsd: \$(angsd 2>&1 | grep -m1 -oE 'version: [^ ]+' | sed 's/version: //')
    END_VERSIONS
    """

    stub:
    """
    mkdir -p ${project}/docs ${project}/workflow
    printf '%s\\n' "${samples}" > ${project}/docs/samples.tsv
    printf '%s\\n' "${contigs}" > ${project}/docs/contigs.tsv
    touch ${project}/locopipe.yaml
    touch versions.yml
    """
}


process LOCOPIPE_RUN {

    tag "$project"

    // cpus / memory come from --threads and --mem, see nextflow.config

    // symlinked rather than copied: loco-pipe writes a lot, and it is already
    // on the shared filesystem
    publishDir "."          , mode: "symlink", overwrite: true, pattern: "${params.project}"

    input:
        path project

    output:
        path "${project}"                    , emit: project
        path "${project}/figures"            , emit: figures, optional: true
        path "locopipe.log"                  , emit: log

    script:
    """
    ${onPath}
    ${TASK_HOME}

    # The project arrives as a symlink, so `cd` into it lands in the real
    # directory and `..` would resolve to ITS parent, not the task dir. Every
    # path out of the project has to be absolute.
    task_dir=\$PWD
    log=\$task_dir/locopipe.log

    cd ${project}

    # -@ matches what Nextflow reserved, so snakemake cannot oversubscribe the
    # allocation it was given
    loco-pipe start -@ ${task.cpus} . 2>&1 | tee "\$log"

    # `loco-pipe start` calls subprocess.run without checking the return code,
    # so it exits 0 even when the workflow failed. Its log is the only reliable
    # signal, and without this a failed run looks like a successful one.
    cd "\$task_dir"
    if grep -qE 'WorkflowError|command exited with non-zero|MissingInputException|Error in rule|^Error' "\$log" ; then
        echo "loco-pipe reported a failure, see locopipe.log" >&2
        tail -40 "\$log" >&2
        exit 1
    fi

    # A run that does nothing at all is a failure too: snakemake can exit
    # cleanly with an empty DAG, and loco-pipe start returns 0 either way, so
    # without this the pipeline reports success having produced no results.
    if [ ! -d "${project}/figures" ] ; then
        echo "loco-pipe produced no figures directory - it did no work." >&2
        echo "Its log follows:" >&2
        tail -40 "\$log" >&2
        exit 1
    fi
    """

    stub:
    """
    mkdir -p ${project}/figures
    echo "stub" > locopipe.log
    """
}
