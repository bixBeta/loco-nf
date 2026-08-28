nextflow.enable.dsl=2

// --sheet and --ref are declared in nextflow.config, since the bind
// computation there reads them while the config is parsed.

// Module Params:
params.help             = false
params.listContigs      = false

// Default Params:
params.id               = "TREX_ID"
params.contigs          = null
params.launch           = true
params.report           = true
params.minlen           = 1000000

// --sif, --sifdir, --threads, --mem and --maxforks are declared in
// nextflow.config, since process directives are resolved before this script
// is parsed.

// Command Line Channels     ~ ~ ~ ~ ~ ~  ~ ~ ~ ~ ~ ~  ~ ~ ~ ~ ~ ~  ~ ~ ~ ~ ~ ~  ~ ~ ~ ~ ~ ~

ch_pin          =    channel.value(params.id)


// ~ ~ ~ ~ ~ ~  ~ ~ ~ ~ ~ ~  ~ ~ ~ ~ ~ ~  ~ ~ ~ ~ ~ ~  ~ ~ ~ ~ ~ ~  ~ ~ ~ ~ ~ ~  ~ ~ ~ ~ ~ ~

if( params.help ) {

log.info """
l  o  c  o  -  n  f      W  O  R  K  F  L  O  W  -  @bixBeta
=======================================================================================================================
Usage:
    nextflow run bixBeta/loco-nf -r main -params-file params.yaml
    nextflow run bixBeta/loco-nf -r main < args ... >

    params.yaml ships with the repo and carries every default, commented.
    Anything on the command line overrides it.

    This is a front-end for loco-pipe ( https://github.com/sudmantlab/loco-pipe ).
    It builds the two tables loco-pipe reads, then runs it inside the image.
    The population genomics itself is entirely loco-pipe's.

Args:
    * --help         : Prints this help documentation
    * --listContigs  : List the contigs in --ref with their lengths, then exit
    * --id           : TREx Project ID
    * --sheet        : sample-sheet.csv < default: looks for sample-sheet.csv in the project dir >
    * --ref          : full path to the reference genome fasta ( must be indexed, .fai alongside )
    * --sif          : full path to the loco-pipe image < default: --sifdir/loco-pipe.sif >
    * --outdir       : directory loco-pipe writes results into < default: locopipe >
                       It lives outside nextflow's work dir, so snakemake keeps
                       its state there and a failed run resumes where it stopped.
    * --threads      : cores handed to snakemake < default: 32 >
    * --report       : render an html report when the run finishes < default: true >
    * --launch       : run loco-pipe after preparing < default: true >
                       --launch false stops after writing the tables, so the
                       grouping can be checked before committing to a long run

    * --contigs      : file listing the contigs to analyse, one per line.
                       Optional: without it, every contig in the .fai at least
                       --minlen long is used.
    * --minlen       : minimum contig length when --contigs is not given < default: 1000000 >

        -----------------------------------------------------------
        Sample Sheet Example: ( comma delimited file )
        |-------------|--------------------------------------|-----------|
        | sample      | bam                                  | group     |
        |-------------|--------------------------------------|-----------|
        | ABLG11920-1 | /workdir/proj/bams/ABLG11920-1.bam   | sunset    |
        | ABLG12067-1 | /workdir/proj/bams/ABLG12067-1.bam   | sunset    |
        | ABLG11918-1 | /workdir/proj/bams/ABLG11918-1.bam   | vermilion |
        | ABLG9871-1  | /workdir/proj/bams/ABLG9871-1.bam    | vermilion |
        |-------------|--------------------------------------|-----------|

        sample is yours: it names the sample in every output and must be unique.
        One bam per sample; if a sample was sequenced more than once, merge the
        bams first. loco-pipe has no notion of pooling several bams per sample.

        bam is the full path. An index is expected next to it ( <bam>.bai );
        loco-pipe will build one if it is missing, which needs the bam directory
        to be writable.

        group is the grouping the analyses are segregated by: species, ecotype,
        population, sampling site, sex, whatever the question is. It becomes
        loco-pipe's population column.

        Several analyses compare groups, so at least two are needed for a fully
        useful run. If there is no grouping a priori, give every sample the same
        value and turn the population level analyses off in locopipe.yaml.

        -----------------------------------------------------------
        Contigs:

        loco-pipe parallelizes by contig, so a fragmented assembly makes far
        too many jobs. Keep the list under ~100 entries; --listContigs prints
        what is in the reference with lengths so the cut is an informed one.

            nextflow run bixBeta/loco-nf -r main --ref /path/ref.fa --listContigs

        A --contigs file may carry an optional second, tab separated column
        holding a short name to use on plots:

            HiC_scaffold_15   15
            HiC_scaffold_16   16
"""

    exit 0
}


log.info """
l  o  c  o  -  n  f      W  O  R  K  F  L  O  W  -  @bixBeta
=========================================================================================================================
trexID       : ${params.id}
sheet        : ${params.sheet}
ref          : ${params.ref}
contigs      : ${params.contigs ?: "auto, every contig >= ${params.minlen} bp"}
outdir       : ${file(params.outdir).toAbsolutePath().normalize()}
launch       : ${params.launch}
threads      : ${params.threads}
maxforks     : ${params.maxforks}
engine       : ${params.engine}
loco-pipe    : ${params.engine == "local" ? params.locopipebin : params.image}
binds        : ${params.runbinds}
"""


// Fail here, with the resolved path, rather than a task dying much later.
// Skipped for -stub-run, which never reads any of these.
def checkRef() {

    if( workflow.stubRun ) return

    if( !params.ref )
        error "No reference provided. Use --ref < full path to the reference fasta >"

    if( !file(params.ref).exists() )
        error "No reference genome at: ${params.ref}"

    // angsd reads the .fai rather than the fasta, and refuses to run if it is
    // not strictly newer, so its absence is worth catching up front.
    if( !file("${params.ref}.fai").exists() )
        error """No fasta index at: ${params.ref}.fai
    Build one with:  samtools faidx ${params.ref}"""
}


// loco-pipe's chr_table takes an optional second column: a short name to show
// on plots. Without it every facet strip carries the full contig name, which is
// then truncated to something unreadable like "...iatus.Sebrube.F.HiC". Prefer a
// trailing number, else the last token.
def contigLabel(String n) {

    // "...HiC_scaffold_15" -> "15", "LG12" -> "12", "chr_big" -> "big"
    def m = (n =~ /(?i).*(?:scaffold|chrom|chr|contig|ctg|LG|SUPER)[_.-]?([A-Za-z0-9]+)$/)
    if( m.matches() ) return m.group(1)

    // Short enough to read as it is. Accessions like NC_044048.1 land here, and
    // must not be shortened to their version suffix, which would collide.
    if( n.length() <= 14 ) return n

    def parts = n.split(/[._-]/).findAll { it }
    return parts ? parts[-1] : n
}


// The reference is the authority on what may be analysed, so the contig list is
// read from the .fai rather than trusted from the sheet.
def faiContigs() {

    def rows = []
    file("${params.ref}.fai").eachLine { line ->
        def f = line.split('\t')
        if( f.size() >= 2 ) rows << [ name: f[0], len: f[1] as Long ]
    }
    return rows
}


// Only the reference is needed to list contigs: this is how you decide what to
// analyse, so it has to work before an image or a sheet exists.
if( params.listContigs ) {

    if( workflow.stubRun ) exit 0

    checkRef()

    def rows = faiContigs().sort { -it.len }
    def keep = rows.findAll { it.len >= params.minlen }

    log.info """
Contigs in ${params.ref}
=========================================================================================================================
${rows.take(200).collect{ String.format('%-45s %15d%s', it.name, it.len, it.len >= params.minlen ? '' : '   ( below --minlen )') }.join('\n')}
${rows.size() > 200 ? "... and ${rows.size() - 200} more" : ""}

${rows.size()} contigs, ${keep.size()} at least ${params.minlen} bp.
${keep.size() > 100 ? "\n  ${keep.size()} is more than the ~100 loco-pipe is comfortable with.\n  Raise --minlen, or give an explicit --contigs file." : ""}
"""

    exit 0
}


// Everything a real run needs. Checked after the utility modes above, which
// deliberately work without an image.
def checkInputs() {

    if( workflow.stubRun ) return

    checkRef()

    // singularity: the .sif must exist. local: the binary must exist.
    if( params.engine == "local" ) {
        if( !file(params.locopipebin).exists() )
            error "No loco-pipe found at: ${params.locopipebin}"
    }
    else {
        def sif = params.image - "file://"
        if( !file(sif).exists() )
            error """No loco-pipe image at: ${sif}
    Build it with containers/build-sif.sh, or point --sif at an existing one."""
    }

    if( !file(params.sheet).exists() )
        error "No sample sheet at: ${params.sheet}. See --help for the columns."

    if( params.contigs && !file(params.contigs).exists() )
        error "No contig list at: ${params.contigs}"
}

checkInputs()


// Read the sheet here rather than in a process, so a malformed sheet is a
// launch time error naming the offending row.
def readSheet() {

    def rows = []
    def seen = [] as Set
    def lines = file(params.sheet).readLines().findAll { it.trim() }

    if( !lines )
        error "sample-sheet: ${params.sheet} is empty"

    def header = lines[0].split(',').collect { it.trim().toLowerCase() }
    ['sample','bam','group'].each {
        if( !header.contains(it) )
            error "sample-sheet: missing required column '${it}'. Found: ${header.join(', ')}. See --help."
    }
    def ix = [ sample: header.indexOf('sample'), bam: header.indexOf('bam'), group: header.indexOf('group') ]

    lines.drop(1).eachWithIndex { line, i ->

        def f = line.split(',').collect { it.trim() }
        def row = [ sample: f[ix.sample], bam: f[ix.bam], group: f[ix.group] ]
        def n = i + 2      // the line number in the file, for a useful message

        if( !row.sample ) error "sample-sheet: line ${n}: every row needs a sample"
        if( !row.bam )    error "sample-sheet: ${row.sample}: missing bam ( full path to the bam file )"
        if( !row.group )  error "sample-sheet: ${row.sample}: missing group, see --help"

        if( !seen.add(row.sample) )
            error "sample-sheet: '${row.sample}' appears more than once. Sample names must be unique, and loco-pipe takes one bam per sample - merge re-sequencing runs first."

        if( !workflow.stubRun && !file(row.bam).exists() )
            error "sample-sheet: ${row.sample}: no bam at ${row.bam}"

        // A relative path resolves against the launch dir here, so it would
        // validate cleanly and then be written verbatim into samples.tsv, where
        // angsd reads it from a different working directory and fails. Store
        // what loco-pipe will actually be able to open.
        row.bam = file(row.bam).toAbsolutePath().normalize().toString()

        rows << row
    }

    if( !workflow.stubRun ) {
        def groups = rows.collect { it.group }.unique().sort()
        if( groups.size() < 2 )
            log.warn "sample-sheet: every sample is in group '${groups[0]}'. Analyses that compare groups will have nothing to compare; turn the population level modules off in ${params.outdir}/locopipe.yaml."
    }

    return rows
}


include {   LOCOPIPE   } from './modules/locopipe'
include {   REPORT     } from './modules/report'


workflow RUN {

    def rows = readSheet()

    // samples.tsv is written here rather than in the task, so it is a plain
    // staged input and shows up in the work dir exactly as loco-pipe will read it
    def samples = "sample_name\tbam\tpopulation\n" +
                  rows.collect { "${it.sample}\t${it.bam}\t${it.group}" }.join("\n") + "\n"

    def contigs
    if( params.contigs ) {
        contigs = file(params.contigs).text
    }
    else {
        def keep = faiContigs().findAll { it.len >= params.minlen }

        // An empty list is not an error loco-pipe would report: it would simply
        // analyse nothing. Catch it here, where the reason is obvious.
        if( !keep && !workflow.stubRun ) {
            def longest = faiContigs().collect { it.len }.max() ?: 0
            error """No contig in ${params.ref} is at least ${params.minlen} bp, so there would be nothing to analyse.
    The longest is ${longest} bp. Lower --minlen, or name the contigs explicitly with --contigs.
    See --listContigs for what is in the reference."""
        }

        if( keep.size() > 100 )
            log.warn "${keep.size()} contigs pass --minlen. loco-pipe parallelizes by contig and is not comfortable much beyond 100; consider raising --minlen or giving --contigs."

        // A short label that is not unique would put two different contigs
        // under one facet, mislabelling the plot rather than just looking
        // untidy. chr_1 and scaffold_1 both shorten to "1", so fall back to the
        // full name wherever that happens.
        def labels = keep.collect { contigLabel(it.name) }
        def seen = [:]
        labels.each { seen[it] = (seen[it] ?: 0) + 1 }

        contigs = [keep, labels].transpose().collect { c, l ->
            "${c.name}\t${seen[l] > 1 ? c.name : l}"
        }.join("\n") + "\n"
    }

    // `loco-pipe init` requires the bam files themselves: it validates that each
    // exists and is readable before laying the project out. Passing the real
    // ones means that check runs inside the container, so a missing bind mount
    // is caught here rather than by angsd much later. Its samples.tsv is still
    // overwritten below, since init puts every sample in one group.
    def bamlist = rows.collect { "'" + it.bam + "'" }.join(' ')

    ch_samples = channel.value(samples)
    ch_contigs = channel.value(contigs)
    ch_bams    = channel.value(bamlist)

    // init records the reference path into locopipe.yaml, which snakemake reads
    // from inside the results directory. Give it the real location rather than
    // the staged symlink in the task directory, which points into the
    // launcher's resolved filesystem.
    def refpath = file(params.ref).toAbsolutePath().normalize().toString()

    // Absolute, because loco-pipe is run with this as its working directory and
    // records absolute paths into locopipe.yaml.
    def outdir = file(params.outdir).toAbsolutePath().normalize().toString()

    // Created here, on the host, before anything is scheduled. The results
    // directory is bind mounted into the image, and Apptainer treats a bind
    // source that does not exist as fatal:
    //   FATAL: container creation failed: ... mount source ... doesn't exist
    // The mkdir inside the task cannot help, since the container has to start
    // before it can run.
    if( !workflow.stubRun ) file(outdir).mkdirs()

    LOCOPIPE( ch_pin, ch_samples, ch_contigs, ch_bams, channel.value(refpath),
              channel.value(outdir), file(params.ref), file("${params.ref}.fai") )

    // The report reads the finished results, so it waits on LOCOPIPE rather
    // than on the outdir existing.
    if( params.launch && params.report ) {

        REPORT( ch_pin, LOCOPIPE.out.versions.map { outdir },
                file("${projectDir}/qmds/loco-report.qmd") )
    }

    if( !params.launch ) {

        log.info """
Preparing ${outdir} without launching it ( --launch false ).
Check the grouping in ${outdir}/docs/samples.tsv, then run the same command
again with --launch true. snakemake keeps its state in that directory, so
nothing already done is repeated.
"""
    }
}


workflow {

    RUN()
}
