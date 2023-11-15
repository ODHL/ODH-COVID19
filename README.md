# ODH-COVID19

## Getting Started
An analysis pipeline designed to obtain raw data and quality control files from `basespace cli`, leverage features of the the `staphb-wf cecret` workflow, generate QC reports,  upload samples to GISAID via `gisaid cli` and prepare samples for upload to NBCI.

## Usage
The pipeline workflow is as follows:
- [Initialize](https://odhl.github.io/SARS_CoV_2_Workflow/ODH-COVID19/getting-started/#initialization)
- [SARSCOV2 Analysis](https://odhl.github.io/SARS_CoV_2_Workflow/ODH-COVID19/analysis/)
- [GISAID Upload](https://odhl.github.io/SARS_CoV_2_Workflow/ODH-COVID19/gisaid/)
- [NCBI Upload Preparation](https://odhl.github.io/SARS_CoV_2_Workflow/ODH-COVID19/ncbi/)

## Pipeline Overview
Deployment of the pipeline requires access to the AWS instance where features are stored, including `staphb-wf cecret`, `basespace cli`, and `gisaid cli`. 

This pipeline performs the following steps:
* INITIALIZE *
1. Creates output project directory, if it doesn't exist.
2. Copies configuration files needed for pipeline execution.

* CECRET *
1. Downloads analysis files for processing directly from `BASESPACE`
2. Creates sample batches dependent on project size and input from config_pipeline.yaml
3. Processes batches individually, including:
3a. Downloads raw data (FASTA) and quality control files from `BASESPACE`
3b. Submits batch to `staphb-wf cecret` workflow
3c. Transforms results into batch level analysis and quality control reports
4. Merges batch outputs into final analysis and quality control reports
5. Removes intermediate files, and working directories

* GISAID *
1. Perform QC for samples that fail N threshold, files added to failed list
2. Perform QC for samples missing metadata files, files added to failed list
3. Transforms passing samples metadata into GISAID required template
4. Transforms passing samples FASTA files into GISAID required FASTA
5. Uploaded metadata and FASTA files to GISAID
6. Merge GISAID ID's into final output report
7. Moves FASTA files to appropriate final directories (IE gisaid_complete) 

* NCBI *
1. Prepares NCBI Attributes batch file
2. Prepares NCBI Metadata batch file
3. Downloads FASTQ files from BASESPACE
4. Return NCBI ID's are added to final output, QC information is tracked

* STATS * 
1. Outputs stats from QC, GISAID, and NCBI uploads to command line

### Help
Review the [UserGuiden](https://odhl.github.io/SARS_CoV_2_Workflow/) documentation for more help!
```
Usage:  -p [REQUIRED] pipeline runmode
        -p options: init, sarscov2, gisaid, ncbi, stat, update
Usage:  -n [REQUIRED] project_id
        -n project id
Usage:  -s [OPTIONAL] subworkflow options
        -s sarscov2: DOWNLOAD, BATCH, CECRET, REPORT, ALL; gisaid: PREP, UPLOAD, QC, ALL
Usage:  -r [OPTIONAL] resume options
        -r Y,N option to resume `-p sarscov2` workflow in progress
Usage:  -t [OPTIONAL] testing options
        -t Y,N option to run test in `-p sarscov2` workflow
```

### Authors
This pipeline was created by Samantha Sevilla Chill, for support of work at the Ohio Department of Health Public Laboratory.