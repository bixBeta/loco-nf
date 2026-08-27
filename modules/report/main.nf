// The report is rendered in a different image from the analysis. loco-pipe.sif
// carries the population genomics; quarto, DT and ImageMagick live in the
// sartools image, which already exists and is what the other bixBeta pipelines
// render their reports with. Keeping them separate avoids rebuilding a 6 GB
// analysis image to gain a document renderer.

process REPORT {

    tag "$id"

    label 'qmds'

    publishDir "pipeline_info", mode: "copy", overwrite: true, pattern: "*.html"

    input:
        val id
        val outdir

    output:
        path "*.html", emit: report

    // sartools style: the template is copied in, rendered, and removed, so only
    // the html is left to publish
    script:
    template 'makeReport.sh'

    stub:
    """
    echo "<html><body>stub report for ${id}</body></html>" > ${id}-loco-report.html
    """
}
