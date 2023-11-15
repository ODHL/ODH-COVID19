# ODH-COVID19

## Getting Started
An analysis pipeline designed to incoporate the `staphb-wf cecret` workflow, generation of QC reports, downloading of raw data and analysis files via `basespace cli`, uploading of samples to GISAID via `gisaid cli` and upload of samples to NBCI `ncbi cli` into one workflow.

## Usage
The pipeline workflow is as follows:
- [initialize pipeline](https://github.com/slsevilla/ODH-COVID19/blob/main/cecret_pipeline/README.md#initialization)
- [run CECRET workflow](https://github.com/slsevilla/ODH-COVID19/blob/main/cecret_pipeline/README.md#running-cecret-workflow)
- [run GISAID upload](https://github.com/slsevilla/ODH-COVID19/blob/main/cecret_pipeline/README.md#running-gisaid-workflow)
- [run NCBI upload preparation](https://github.com/slsevilla/ODH-COVID19/blob/main/cecret_pipeline/README.md#running-ncbi-workflow)

## Pipeline Overview
Deployment of the pipeline requires access to the AWS instance where features are stored, including `staphb-wf cecret`, `basespace cli`, and `gisaid cli`. 

This pipeline performs the following steps:
* INITIALIZE *
1. Creates output project directory, if it doesn't exist.
2. Copies configuration files needed for pipeline execution.

* CECRET *
1. Downloads analysis files for processing directly from BASESPACE
2. Creates sample batches dependent on project size and input from config_pipeline.yaml
3. Processes batches individually, including:
3a. (If QC report flag is ON) downloads and processes BASESPACE analysis files
3b. Downloads sample fastq files directly from BaseSpace
3c. Submits batch to `staphb-wf cecret` workflow
3d. (If QC report flag is ON) process output QC data from CECRET and BASESPACE
3e. Generates combined PANGOLIN and NEXTCLAD final analysis report
4. Removes intermediate files, and working directories

* GISAID *
1. Perform QC for samples that fail N threshold, files added to failed list
2. Perform QC for samples missing metadata files, files added to failed list
3. All samples passing QC have metadata added to GISAID batch upload template, FASTA files are added to merged FASTA file
4. Samples are uploaded to GISAID
5. Return GISAID ID's are added to final output, QC information is tracked
6. (If reject flag is on) processes rejected samples
6a. Adds rejection note to rejected samples
6b. Moves FASTA files to the rejected directory

* NCBI *
1. Prepares NCBI Attributes batch file
2. Prepares NCBI Metadata batch file
3. Downloads FASTQ files from BASESPACE
4. (If reject flag is ON) processes uploaded samples
4a. Return NCBI ID's are added to final output, QC information is tracked

* STATS * 
1. Outputs stats from QC, GISAID, and NCBI uploads to command line

### Help
Review the GitHub [pages](https://slsevilla.github.io/ODH-COVID19/ODH-COVID19/maintenance/) documentation for more help!

Usage:  -m [REQUIRED] pipeline mode options
        -m options: init, cecret, gisaid, ncbi, stats, update
Usage:  -n [REQUIRED] project_id
        -n project id
Usage:  -q [OPTIONAL] qc_flag
        -q Y,N option to run QC analysis (default Y)
Usage:  -t [OPTIONAL] testing_flag
        -t Y,N option to run test settings (default N)
Usage:  -p [OPTIONAL] partial_run
        -p Y,N option to run partial run settings (default N)
Usage:  -r [OPTIONAL] reject_flag
        -r Y,N option to run GISAID or NCBI processed samples (default N)

### Authors
This pipeline was created by Samantha Sevilla Chill, for support of work at the Ohio Department of Health Public Laboratory.