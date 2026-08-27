import click
import glob
import os
from pathlib import Path
import re

class BAMfile(click.ParamType):
    """A CLI class to validate a BAM file as input. Checks for presence, and returns the absolute path"""
    name = "bam_file"
    def __init__(self):
        super().__init__()
        self.re_ext = re.compile(r"\.(bam)$", re.IGNORECASE)
        self.inv_pattern = re.compile(r'[^a-z0-9._-]+', re.IGNORECASE)

    def convert(self, value, param, ctx):
        infiles = []
        filepath = Path(value)
        if not filepath.exists():
            self.fail(f"{value} was not found.", param, ctx)

        if not filepath.is_dir():
            _f = filepath.resolve().as_posix()
            if not self.re_ext.search(_f):
                self.fail(f"{value} does not end with the accepted extensions for alignment files: .bam (case insensitive).")
            infiles.append(_f)
        else:
            for i in filepath.glob("*"):
                if i.is_file() and self.re_ext.search(i.name):
                    infiles.append(i.resolve().as_posix())

        # name and permission validations
        for _file in infiles:
            if not os.access(_file, os.R_OK):
                self.fail(f"Alignment file {_file} does not have user read permission.", param, ctx)
            #if self.inv_pattern.search(_file):
            if self.inv_pattern.search(os.path.basename(_file)):
                self.fail(f"Invalid characters detected in file name {_file}. Valid file names may contain only:\n  - A-Z 0-9 characters (case insensitive)\n  - . (period)\n  - _ (underscore)\n  - - (dash)")

        if len(infiles) < 1:
            self.fail(f"There were no files ending with the accepted alignment extensions .bam (case insensitive) in {value}.")

        else:
            return infiles


LOCOFILES = [
    'config.yaml',
    'locopipe.yaml',
    'docs/contigs.tsv',
    'docs/samples.tsv',
    'workflow/envs/angsd.yaml',
    'workflow/envs/loco-pipe.yaml',
    'workflow/envs/lostruct.yaml',
    'workflow/envs/ohana.yaml',
    'workflow/envs/pcangsd.yaml',
    'workflow/envs/r.yaml',
    'workflow/envs/samtools.yaml',
    'workflow/pipelines/loco-pipe.smk',
    'workflow/rules/combine_snp_list.smk',
    'workflow/rules/get_depth_filter_global.smk',
    'workflow/rules/get_depth_global.smk',
    'workflow/rules/get_fst.smk',
    'workflow/rules/get_heterozygosity.smk',
    'workflow/rules/get_maf.smk',
    'workflow/rules/get_site_list_global.smk',
    'workflow/rules/get_theta.smk',
    'workflow/rules/pipeline_prep.smk',
    'workflow/rules/run_lostruct_global.smk',
    'workflow/rules/run_ohana.smk',
    'workflow/rules/run_pcangsd.smk',
    'workflow/rules/snp_calling_global.smk',
    'workflow/rules/subset_snp_list.smk',
    'workflow/scripts/get_depth_filter.R',
    'workflow/scripts/plot_SFS.R',
    'workflow/scripts/plot_fst.R',
    'workflow/scripts/plot_heterozygosity.R',
    'workflow/scripts/plot_lostruct_mds.R',
    'workflow/scripts/plot_lostruct_outlier_pca.R',
    'workflow/scripts/plot_ohana_admixture.R',
    'workflow/scripts/plot_pcangsd_pca.R',
    'workflow/scripts/plot_theta_by_window.R',
    'workflow/scripts/run_lostruct.R',
    'workflow/scripts/summarize_pcangsd_for_lostruct.R'
]
def valid_dir(dir):
    pattern = f"{dir}/**/*"
    files_present = []
    files_absent= []
    for i in glob.glob(pattern, recursive=True):
        if os.path.isfile(i) and "profiles/" not in i:
            files_present.append(i.lstrip(f"{pattern}/"))
    for i in LOCOFILES:
        if i not in files_present:
            files_absent.append(i)
    return files_absent