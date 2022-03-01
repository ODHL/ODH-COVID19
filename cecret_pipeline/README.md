# ODH-COVID19
Welcome to the ODH-COVID19 Analysis workflow SOP!

## Getting Started
Deployment of the workflow requires access to the AWS instance where the `staphb-wf cecret` workflow is stored.
1. Change working directory to the ODH-COVID19 repository
> ```
> cd analysis_workflow
> ```

2. Review the tutorial information below.

## Pipeline Options
The workflow has a multiple options:
> ```bash
> bash run_cecret.sh
> Usage: -p pipeline
> 	-p options: init, run, gisaid, update
> Usage:  -n name of the project
> 	-n for example OH-VH00123-2201234
> ```

Example commands:
> ```bash
> #Initialize Pipeline
> bash run_cecret.sh -p init -n OH-VH00123-2201234
> 
> #Execute CECRET, QC workflow
> bash run_cecret.sh -p run -n OH-VH00123-2201234
> 
> #Execute GISAID workflow
> bash run_cecret.sh -p gisaid -n OH-VH00123-2201234
> 
> #Execute update of workflow features
> bash run_cecret.sh -p update
> ```

Explanation of pre-processing:
- initialize (required): This must be performed before any pipeline execution (-p run) can be performed. This will copy the necessary config files needed to run the pipeline to the provided output directory.

Explanation of processing steps:
- run - This will run the cecret pipeline, on a local terminal, as well as the QC report.
- gisaid - This will run the GISAID upload of samples, assign EPI ID's and determine errors.

Explanation of other steps:
- update - This will run a pipeline update, on a local terminal, updating the cecret features.

## Complete Pipeline Workflow
* Workflow of Pipeline *
1. Creates list of files within project directory to be reviewed
2. Perform QC for samples that fail N threshold, files added to failed list
3. Perform QC for samples missing metadata files, files added to failed list
4. All samples passing QC have metadata added to GISAID batch upload template, file names are added to pass list
5. All samples passing QC are added to merged FASTA file

* GISAID Upload *
1. Document N samples passing QC and N samples failing in tracking file, columns D and E
2. Open batched_metadata_input.csv file
3. Open timestamp_ProjectName_metadata.xls file
4. Paste batched_metadata_input.csv into second tab of DATE_ProjectName_metadata.xls
5. Fix date error with excel conversion 
6. Upload to timestamp_ProjectName_metadata.xls and batched_merged_fasta.fasta files to GISAID batch uploader

* GISAID Error *
1. Download the timestamp_ProjectName_metadata.xls file with notes from GISAID
2. Copy virus name and error notes columns to /ProjectName/fastas_GISAID_errors/error_log.txt
3. Document N samples passing QC and N samples failing in tracking file, columns F and G
4. Run "error" pipeline

## Preparing Config
There is one config requirement for this pipeline, found /output/dir/gisaid_config.txt, after initialization. 
- Update the config file, as necessary, following the format below:
  - Required:
    - Submitter: enter your GISAID-Username
    - Type: default must remain betacoronavirus
    - Passage details/history: Original, Vero
    - Host: Human, Environment, Canine, Manis javanica, Rhinolophus affinis, etc 
    - Gender: set to unkonwn for all
    - Patient status: Hospitalized, Released, Live, Deceased, or unknown
    - Outbreak: Date, Location, type of gathering (Family cluster, etc.)
    - Last vaccinated: provide details if applicable
    - Treatment: Include drug name, dosage
    - Sequencing technology: Illumina Miseq, Sanger, Nanopore MinION, Ion Torrent, etc.
    - Originating lab: Where sequence data have been generated and submitted to GISAID
    - Address
    - Submitting lab
    - Address
    - Authors: a comma separated list of Authors with complete First followed by Last Name

  - Optional:
    - Additional location information: Cruise Ship, Convention, Live animal market
    - Additional host information: Patient infected while traveling in …. 
    - Sampling Strategy: Sentinel surveillance (ILI), Sentinel surveillance (ARI), Sentinel surveillance (SARI), Non-sentinel-surveillance (hospital), Non-sentinel-surveillance (GP network), Longitudinal sampling on same patient(s), S gene dropout
    - Specimen source: Sputum, Alveolar lavage fluid, Oro-pharyngeal swab, Blood, Tracheal swab, Urine, Stool, Cloakal swab, Organ, Feces, Other
    - Assembly method: CLC Genomics Workbench 12, Geneious 10.2.4, SPAdes/MEGAHIT v1.2.9, UGENE v. 33, etc.
    - Coverage: 70x, 1,000x, 10,000x (average)

## Preparing Directory folder
The pipeline assumes that the directory structure for input is as follows:
project_name
- Fastas_not_complete
  - fasta1_consensus.fasta
  - fasta2_consensus.fasta
  - fasta3_consensus.fasta
  
## Expected Outputs
- project_dir
  - Fastas - GISAID Not Complete
    - fasta1.fasta
    - error_log.txt
  - fastas_GISAID_errors
  - fastas_GISAID_uploaded
  - GISAID_logs
    - timestamp
      - qc_passed.txt
      - qc_failed.txt
      - batched_metadata_input.csv
      - batched_fasta_input.fasta
      - project_name_metadata.xls
  - gisaid_config.yaml
    
#### Example qc_failed.txt
This file includes sample and QC information for all failed samples, either providing note on missing metadata or on N values above threshold
```
#filename, reason for failure
/Users/sevillas2/Desktop/APHL/test_data/OH-123/2021063918_consensus.fasta	Missing metadata
/Users/sevillas2/Desktop/APHL/test_data/OH-123/seq2.fasta	Missing metadata
/Users/sevillas2/Desktop/APHL/test_data/OH-123/seq3.fasta 	 53% N
/Users/sevillas2/Desktop/APHL/test_data/OH-123/seq4.fasta 	 53% N
```
#### Example qc_passed.txt
This file will include sample information that has been added to metadata file, and that has fasta file data merged 
```
>something/goes/here_SC1234/2020/seq1.fasta
>something/goes/here_SC5678/2021/seq2.fasta
```

