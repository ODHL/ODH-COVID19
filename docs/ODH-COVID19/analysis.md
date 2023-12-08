### Running Analysis workflow

0. Initialization has been complete (see Getting Started for details)
1. Change working directory to the analysis pipeline directory
2. Run analysis workflow
    - There are several subworkflows that are available to the user. These include: 
        - `DOWNLOAD`: Downloads analysis files for processing directly from `BASESPACE`
        - `BATCH`: Creates sample batches dependent on project size and input from config_pipeline.yaml
        - `ANALYZE`: Processes batches individually, including:
            - Downloads raw data (FASTA) and quality control files from `BASESPACE`
            - Submits batch to `staphb-wf cecret` workflow
            - Transforms results into batch level analysis and quality control reports
        - `REPORT`: Merges batch outputs into final analysis and quality control reports
        - `CLEAN`: Removes intermediate files, and working directories
        - `ALL`: Runs all of the above steps, sequentially

```
#1 change to the working directory
cd SARS_CoV_2_Workflow

#2A run workflow command: sarscov2
bash run_analysis_pipeline.sh -p sarscov2 -n name_of_project

#2B run workflow command: sarscov2; subworkflow DOWNLOAD
bash run_analysis_pipeline.sh -p sarscov2 -n name_of_project -s DOWNLOAD
```