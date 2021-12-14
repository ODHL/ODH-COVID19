# ODH-COVID19
Ohio COVID project

## Overview
The pipeline has the following workflow:
* Initialize *
1. Create output directory
2. Create copy of config file, GISAID metadata input file in output directory

* Run *
1. Create list of files within project directory to be reviewed
2. Perform QC for samples that fail N threshold, files added to failed list
3. Perform QC for samples missing metadata files, files added to failed list
4. All samples passing QC have metadata added to template, files added to pass list
5. All samples passing QC are added to merged FASTA file

* GISAID Upload *
1. Open batched_metadata_input.csv file
2. Open DATE_ProjectName_metadata.xls file
3. Paste batched_metadata_input.csv into X tab of DATE_ProjectName_metadata.xls
4. Upload to DATE_ProjectName_metadata.xls and batched_merged_fasta.fasta files to GISAID batch uploader

## Running Script
To complete the pipeline, first the output directory must be initialized. Once this command has been completed, then the run command may be run.

The pipeline requires two inputs: 
- p options: initialize, run, rerun
  - initialize will create output dir, create config file in output_dir
  - run will run the script according to workflow
- o options: path to the desired output directory

This taks the format of the following command:
sh run_gisaid.sh \
-p [pipeline_options] \
-o [output_dir]

For example, to complete the pipeline in the output directory /Users/sevillas2/Desktop/APHL/demo/OH-123, perform the following steps.
```
### Step 1: 
#### Pipeline: Initialize
sh run_gisaid.sh -p initialize -o /Users/sevillas2/Desktop/APHL/demo/OH-123

### Step 2
#### Open and edit the gisaid_config.yaml file with approriate directories and input, located in the output directory. Use the information below for help filling the config.

### Step 3
#### Pipeline: Run
sh run_gisaid.sh -p run -o /Users/sevillas2/Desktop/APHL/demo/OH-123

```
## Config description
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

## Output Information
### Before processing
- project_dir
  - Fastas - GISAID Not Complete
    - fasta1.fasta
    - fasta2.fasta
    - fasta3.fasta
    - original_metadata.csv

### After processing
- project_dir
  - Fastas - GISAID Not Complete
    - fasta1.fasta
    - fasta2.fasta
    - fasta3.fasta
  - gisaid_config.yaml
  - config.yaml
  - GISAID_Complete
    - timestamp
      - passed_qc.txt
      - failed_qc.txt
      - batched_metadata_input.csv
      - batched_fasta_input.fasta

### Example outputs
#### Example failed_qc.txt
This file includes sample and QC information for all failed samples, either providing note on missing metadata or on N values above threshold
```
#filename, reason for failure
/Users/sevillas2/Desktop/APHL/test_data/OH-123/2021063918_consensus.fasta	Missing metadata
/Users/sevillas2/Desktop/APHL/test_data/OH-123/seq2.fasta	Missing metadata
/Users/sevillas2/Desktop/APHL/test_data/OH-123/seq3.fasta 	 53% N
/Users/sevillas2/Desktop/APHL/test_data/OH-123/seq4.fasta 	 53% N
```

#### Example passed_qc.txt
This file will include sample information that has been added to metadata file, and that has fasta file data merged 
```
>something/goes/here_SC1234/2020/seq1.fasta
>something/goes/here_SC5678/2021/seq2.fasta
```

## Metadata Creation
The following are required headers for the final metadata file. Input location is described below, indicating data is pulled from the config or the pipeline script, with the * indicating optional data:
- Submitter - config
- FASTA filename - gisaid.sh
- Virus name- gisaid.sh
- Type - config
- Passage details/history - config
- Collection date - gisaid.sh
- Location - gisaid.sh
- * Additional location information - config
- Host - config
- * Additional host information - config
- * Sampling Strategy - config
- Gender - config
- Patient age - gisaid.sh
- Patient status - config
- *Specimen source - config
- Outbreak - config
- Last vaccinated - config
- Treatment - config
- Sequencing technology - config
- * Assembly method - config
- * Coverage - config
- Originating lab - config
- Address - config
- * Sample ID given by the originating laboratory - gisaid.sh
- Submitting lab - config
- Address - config
- * Sample ID given by the submitting laboratory - gisaid.sh
- Authors - config