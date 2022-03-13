# ODH-COVID19

## Getting Started
A bash wrapper designed to incoporate the `staphb-wf cecret` workflow, generation of QC reports, and uploading of samples to GISAID via `gisaid cli` into one analysis pipeline.

## Pipeline Overview
Deployment of the workflow requires access to the AWS instance where the `staphb-wf cecret` workflow is stored. The workflow also deploys `gisaid cli`, where a version has been installed and maintained on the AWS instance.

The workflow design is as follows:
- initialize pipeline
- run CECRET workflow and generate QC report
- run GISAID upload

## Usage
### Help
Usage:  -p pipeline options
-e      -p options: init, run, gisaid, update
Usage:  -n project_name
-e      -n project name
Usage:  -q qc_flag
-e      -q Y flag of whether to run QC analysis on files
Usage:  -t testing_flag
-e      -t Y flag indicate if run is a test

### Initialization (REQUIRED)
Deployment of either run feature (CECRET or GISAID) requires the initalization of the pipeline. This step will create the directory structure needed for the pipeline, will create log files for documentation and will copy the necessary manifests and config files to their appropriate locations for pipeline control.

1. Change working directory to the analysis pipeline directory
2. Select the initialization flag (-p init) on the project (-n name_of_project) and select whether a QC report (-q) should be generated (Y or N)

```

cd analysis_pipeline

bash run_analysis_pipeline.sh -p init -n name_of_project -q Y

```

Expected output:
-- /name_of_project/
---- /analysis/
------ /fasta/
------ /intermed/
------ /ivar/
---- /cecret/
---- /fastq/
---- /logs/
------ 22-02-23_cecret.config
-------- gisaid_log.txt
-------- multiqc_config.yaml
-------- pipeline_config.yaml
-------- pipeline_log.txt
------ /qc/
-------- covid19_qcreport
------ /tmp/
-------- fastqc
-------- unzipped

### Update Configuration Files (REQUIRED)
After completion of the initialization step, configuration files must be edited according to the project. These include:

#### 1. Pipeline Config
- Description: This configuration file controls all metadata associated with the project, as well as pipeline specific parameters. Within this configuration file PANGOLIN software versions can be selected, final results file name can be updated, and batch size can be controlled. GISAID-related parameters (optional and required) are also included in this configuration file.
- Location: /name_of_project/logs/pipeline_conifg.yaml

#### 2. CECRET Config
- Description: This configuration file controls all the features associated with the CECRET pipline (see below for pipeline maintainence). Editing this configuration file is not recommended outside of pipeline maintenance (see below). Two versions of the configuration file are in use:

  1. date_of_creation_cecret.config
  2. date_of_creation_cecret_partial.config

If a QC report is not required (-q N), the partial configuration (#2) is used. This will only run a subset of the entire CECRET pipeline, increasing the pipeline speed and decreasing overall disc space required. 
- Location: /name_of_project/logs/date_of_creation_cecret.config or /name_of_project/logs/date_of_creation_cecret_partial.config

#### 3. MultiQC Config
-  Description: THis configuration file controls all the features associated with the MultiQC report generated upon pipeline completion (-q Y). Editing this configuration file is not recomended outside of pipeline maintainence (see below).
- Location: /name_of_project/logs/multiqc_config.yaml

### Running CECRET workflow (REQUIRED)
This wrapper performs the following steps:
- downlaods the required files for processing complete project (file type dependent on whether QC report is to be downloaded) directly from BaseSpace
- creates sample batches dependent on project size and input from pipeline_config.yaml (batch_limit)
- processes batches individually, performing a clean-up of intermediate files to ensure disc space of AWS instance is most effeciently utilized
-- downloads sample fastq files directly from BaseSpace
-- (if QC report required) process analysis files
-- submits batch to `staphb-wf cecret` workflow
-- (if QC report required) process output QC data from cecret workflow
-- (if QC report required) generates QC report from CECRET and BaseSpace output
-- generates combined PANGOLIN and NEXTCLAD final analysis report
-- removes intermediate files, and working directories

0. Ensure initialization has been complete
0. Ensure configuration files have been updated
1. Change working directory to the analysis pipeline directory
2. Select the run flag (-p run) on the project (-n name_of_project) and select whether a QC report (-q) should be generated (Y or N)

```
# 1. move to working dir
cd analysis_pipeline

# 2A. run with QC report
bash run_analysis_pipeline.sh -p run -n name_of_project -q Y

# 2B. run without QC report
bash run_analysis_pipeline.sh -p run -n name_of_project -q N

```

### Running GISAID workflow (OPTIONAL)
TODO: write up description when implementation is complete

```
cd analysis_pipeline

bash run_analysis_pipeline.sh -p gisaid -n name_of_project
```

## Tutorial
Testing parameters have been created in order to test the settings of the pipeline with new data, or train new staff on it's usage. Test settings will download a complete project, but
will only run two batches, with two samples in each batch. Initialization, run, and QC parameters should be reviewed below as they may be used in conjunction with the test setting.

1. Change working directory to the analysis pipeline directory
2. Run test on project name_of_project with the testing (-t) flag turned on (Y) and qc flag (-q) off (N)

```
# 1. move to working dir
cd analysis_pipeline

# 2. run with testing flag on, without QC report
bash run_analysis_pipeline.sh -p test -n name_of_project -t Y -q N
```

## TO DO: everything below
## Pipeline Maintanence
### Reference files
- include information on archiving
- where source documentation is
https://github.com/artic-network/artic-ncov2019/tree/master/primer_schemes/nCoV-2019/V4.1

### configuration updates
- include how to download cecret config
- include information on archiving
- include information on pipeline partial features
- include multiqc reference link for updating
- when GISAID is completed - anything needed for this

### updating features
- how to update CECRET (-p update)
- figure out how to update gisaid - maybe add to update flag above
- how to update pangolin version (needs to be done in config and in run_pipeline file (add numerics, name must match docker, add link)

## TO DO: Incorporate GISAID notes below when complete
1. Open tracking document
2. Input number of samples to be processed in column C
3. Run "initialize" pipeline; edit /output/dir/gisaid_config.yaml with project name
4. Run "batch" pipeline

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
- Fastas - GISAID Not Complete
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
#### Example qc_pasied.txt
This file will include sample information that has been added to metadata file, and that has fasta file data merged 
```
>something/goes/here_SC1234/2020/seq1.fasta
>something/goes/here_SC5678/2021/seq2.fasta
```


## GISAID CLI notes
### Authenticate 
To run tests, use client_id:
--client_id: TEST-EA76875B00C3

For sample uploads, use client_id:


```
#Example
cli2 authenticate --client_id TEST-EA76875B00C3 --username sevillas2
```
