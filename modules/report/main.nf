// The report is rendered in a different image from the analysis. loco-pipe.sif
// carries the population genomics; quarto, DT and ImageMagick live in the
// sartools image, which already exists and is what the other bixBeta pipelines
// render their reports with. Keeping them separate avoids rebuilding a 6 GB
// analysis image to gain a document renderer.

process REPORT {

    tag "$id"

    label 'qmds'

    publishDir "pipeline_info", mode: "copy", overwrite: true, pattern: "*.html"
    // named exactly, not *.png: the task directory is full of the figures
    // copied out of the outdir for rendering, and none of those belong here
    publishDir "pipeline_info", mode: "copy", overwrite: true, pattern: "run_stats.png"

    input:
        val  id
        val  outdir
        path qmd
        val  manifest   // figure fingerprint; only here to invalidate a stale report

    output:
        path "*.html", emit: report
        path "run_stats.png", emit: stats, optional: true

    // The qmd is a staged path input rather than a ${projectDir} reference:
    // Nextflow binds the directories of declared inputs, but not the pipeline
    // source, so reading it from projectDir failed inside the container with
    //   cp: cannot stat '.../qmds/loco-report.qmd': No such file or directory
    script:
    template 'makeReport.sh'

    stub:
    """
    echo "<html><body>stub report for ${id}</body></html>" > ${id}-loco-report.html
    """
}
