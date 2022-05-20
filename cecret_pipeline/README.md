# ODH-COVID19

## Getting Started
An analysis pipeline designed to incoporate the `staphb-wf cecret` workflow, generation of QC reports, downloading of raw data and analysis files via `basespace cli`, uploading of samples to GISAID via `gisaid cli` and upload of samples to NBCI `ncbi cli` into one workflow.

## Usage
The pipeline workflow is as follows:
- [initialize pipeline](https://github.com/slsevilla/ODH-COVID19/blob/main/cecret_pipeline/README.md#initialization)
- [run CECRET workflow](https://github.com/slsevilla/ODH-COVID19/blob/main/cecret_pipeline/README.md#running-cecret-workflow)
- [run GISAID upload](https://github.com/slsevilla/ODH-COVID19/blob/main/cecret_pipeline/README.md#running-gisaid-workflow) (IN PROGRESS)
- run NCBI upload (IN PROGRESS)

## Pipeline Overview
Deployment of the pipeline requires access to the AWS instance where features are stored, including `staphb-wf cecret`, `basespace cli`, `gisaid cli` and `ncbi cli`. 

This pipeline performs the following steps:
* INITIALIZE *

* RUN *
1. downloads analysis files for processing directly from BASESPACE
2. creates sample batches dependent on project size and input from config_pipeline.yaml
3. processes batches individually, including:
3a. (if QC report required) downloads and processes BASESPACE analysis files
3b. downloads sample fastq files directly from BaseSpace
3c. submits batch to `staphb-wf cecret` workflow
3d. (if QC report required) process output QC data from CECRET and BASESPACE
3e. generates combined PANGOLIN and NEXTCLAD final analysis report
4. removes intermediate files, and working directories

* GISAID *
1. Perform QC for samples that fail N threshold, files added to failed list
2. Perform QC for samples missing metadata files, files added to failed list
3. All samples passing QC have metadata added to GISAID batch upload template, FASTA files are added to merged FASTA file
4. Samples are uploaded to GISAID
5. Return sample ID's are added to final output, QC information is tracked

### Help
Usage:  -r run options
-e      -r options: init, run, gisaid, ncbi, update
Usage:  -n project_name
-e      -n project name
Usage:  -q qc_flag
-e      -q option to run QC analysis (default "Y")
Usage:  -t testing_flag
-e      -t option to run test parameters (default "N")
Usage:  -p partial_flag
-e      -p option to run partial run parameters (default "N")

### Initialization
Deployment of run features (CECRET, GISAID, NCBI) requires the initalization of the pipeline. This step will create the directory structure needed for the pipeline, will create log files for documentation and will copy the necessary manifests and config files to their appropriate locations for pipeline control.

1. Change working directory to the analysis pipeline directory
2. Select the initialization flag (-r init) on the project (-n name_of_project)

```

cd analysis_pipeline

bash run_analysis_pipeline.sh -r init -n name_of_project

```

Initialization output:
-- /name_of_project/
---- /analysis/
------ /fasta/
-------- /not_uploaded/
-------- /uploaded/
-------- /partial_upload/
-------- /failed/
------ /intermed/
---- /cecret/
---- /fastq/
---- /logs/
------ config_cecret.config
------ config_multiqc.yaml
------ config_pipeline.yaml
------ gisaid_log.txt
------ pipeline_log.txt
------ /qc/
-------- covid19_qcreport
------ /tmp/
-------- fastqc
-------- unzipped

### Configuration Files
After completion of the initialization step, configuration files may be edited according to the project. These include:

#### 1. PIPELINE Config
- Description: This configuration file controls all metadata associated with the project, as well as pipeline specific parameters. Within this configuration file software versions can be selected and batch size can be controlled. GISAID-related parameters (optional and required) are also included in this configuration file.
- Location: /name_of_project/logs/config_pipeline.yaml

#### 2. CECRET Config
- Description: This configuration file controls all the features associated with the CECRET workflow.
- Location: /name_of_project/logs/config_cecret.config

#### 3. MULTIQC Config
-  Description: This configuration file controls all the features associated with the MULTIQC report generated upon pipeline completion.
- Location: /name_of_project/logs/config_multiqc.yaml

### Running CECRET workflow

0. Ensure initialization has been complete
1. Change working directory to the analysis pipeline directory
2. Select the run flag (-r run) on the project (-n name_of_project). (OPTIONAL) select whether a QC report (-q) should be generated (default "Y")

```
# 1. move to working dir
cd analysis_pipeline

# 2A. run with QC report
bash run_analysis_pipeline.sh -r run -n name_of_project -q Y

# 2B. run without QC report
bash run_analysis_pipeline.sh -R run -n name_of_project -q N

```

### Running GISAID workflow (OPTIONAL)
TODO: write up description when implementation is complete

```
cd analysis_pipeline

bash run_analysis_pipeline.sh -p gisaid -n name_of_project
```

## Tutorial
Testing parameters have been created in order to test the settings of the pipeline with new data, or train new staff on it's usage. Test settings will download a complete project, but will only run two batches, with two samples in each batch. Initialization, run, and QC parameters should be reviewed below as they may be used in conjunction with the test setting.

1. Change working directory to the analysis pipeline directory
2. Run test on project name_of_project with the testing (-t) flag turned on (Y).(OPTIONAL) select whether a QC report (-q) should be generated (default "Y")

```
# 1. move to working dir
cd analysis_pipeline

# 2. run with testing flag on, without QC report
bash run_analysis_pipeline.sh -r test -n name_of_project -t Y -q N
```

## Configuration Files
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
   - Originating lab: Where sequence data have been generated
   - Address: Address of originating lab
   - Submitting lab: Where sequence data is being submitted to GISAID
   - Address: Address of submitting lab
   - Authors: a comma separated list of Authors with complete First followed by Last Name
- Optional:
   - Additional location information: Cruise Ship, Convention, Live animal market
   - Additional host information: Patient infected while traveling in …. 
   - Sampling Strategy: Sentinel surveillance (ILI), Sentinel surveillance (ARI), Sentinel surveillance (SARI), Non-sentinel-surveillance (hospital), Non-sentinel-surveillance (GP network), Longitudinal sampling on same patient(s), S gene dropout
   - Specimen source: Sputum, Alveolar lavage fluid, Oro-pharyngeal swab, Blood, Tracheal swab, Urine, Stool, Cloakal swab, Organ, Feces, Other
   - Assembly method: CLC Genomics Workbench 12, Geneious 10.2.4, SPAdes/MEGAHIT v1.2.9, UGENE v. 33, etc.
   - Coverage: 70x, 1,000x, 10,000x (average)
 
## Software
### GISAID specific features
GISAID CLI requires authentication. Authentication must be performed every 100 days. 

To run tests, use client_id:
--client_id: TEST-EA76875B00C3

For sample uploads, use client_id obtained by emailing:
--email: clisupport@gisaid.org

User specific ID list
--cliend_id: cid-1e895d886d3a6

```
# Example test authentication
cli2 authenticate --client_id TEST-EA76875B00C3 --username sevillas2

# Example full authentication
cli2 authenticate --cliend_id [insert id] --username [username]
```
 
## Pipeline Maintanence
### Configuration Files
#### Active Configs. All configuration files should adopt a standard nomenclature: config_typeofconfig.yaml. For example, config_pipeline.yaml for a pipeline config file. Accepted typeofconifg are: pipeline,cecret,multiqc.
#### In-active Configs. Any updated configuration files should follow archiving practices described below.

### Reference Files
#### Active References. All references files should adopt a standard nomenclature: ref_typeofref_id.yaml. For example, config_pipeline.yaml for a pipeline config file. Accepted typeofconifg are: pipeline,cecret,multiqc.
#### In-active Configs. Any updated configuration files should follow archiving practices described below.

### Archiving
Supporting Files. All configuration and reference files should be kept for documentation purposes. The outdated file should be copied with the naming schema: config_typeofconfig_dateofarchive.ext or reference_referencetype_dateofarchive.ext. Reference file README must be updated to indicate the new source of the reference file in use. All changes must be backed up on GITHUB within one week.

### Once it is determined that the pipeline is needed to be updated (either configuration files, reference files) changes should be made to the local repository. GITHUB must be updated with these changes and a new version should be tagged. If changes are backwards compatible a minor version change can be implemented. If the change is not backwards compatible, then a major version change should be implemented.

### Software Updates 
#### CECRET
The CECRET pipeline can be updated through the analysis workflow. This will update the pipeline and any related script/pipeline/docker changes. This would not constitute an archiving event.

```
cd analysis_pipeline

bash run_analysis_pipeline.sh -p update
```

#### PANGOLIN, NEXTCLADE
New versions of PANGOLIN and NEXTCLADE have a significant impact on the results generated from the analysis workflow. While these should be regularly reviewed, updating these will require a change to the config and to the workflow run file (run_analysis_pipeline.sh). Follow the nomenclature, documentation, and archiving strategies described under configuration updates. This would consistitute a minor archiving event.

1. Update configuration file
	- Updates must be made to the configuration file to provide users with the newest version
2. Update analysis run_file
	- Updates must be to the run_analysis_pipeline.sh to conver the user selected feature to the correct software version.
TODO: create a file that can be edited rather than needed to edit the run_analysis_pipeline.sh

### Reference files
- include information on archiving
- where source documentation is
https://github.com/artic-network/artic-ncov2019/tree/master/primer_schemes/nCoV-2019/V4.1
This would constitute a minor archiving event.

### Primers
TODO update which primers are used. This would consistitute a minor archiving event.
