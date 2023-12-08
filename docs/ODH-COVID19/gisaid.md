### Running GISAID workflow

0. `sarscov2` workflow has been completed (see Analysis for more details)
1. Change working directory to the analysis pipeline directory
2. Run analysis workflow

    - There are several subworkflows that are available to the user. These include: 

        - `PREP`: 

            - Perform QC for samples that fail N threshold, files added to failed list 
            - Perform QC for samples missing metadata files, files added to failed list
            - Transforms passing samples metadata into GISAID required template
            - Transforms passing samples FASTA files into GISAID required FASTA

        - `UPLOAD`: 

            - Uploaded metadata and FASTA files to GISAID

        - `QC`: 

            - Merge GISAID ID's into final output report
            - Moves FASTA files to appropriate final directories (IE gisaid_complete) 

        - `ALL`: Runs all of the above steps, sequentially

```
#1 change to the working directory
cd SARS_CoV_2_Workflow

#2A run workflow command: gisaid
bash run_analysis_pipeline.sh -p gisaid -n name_of_project

#2B run workflow command: sarscov2; subworkflow PREP
bash run_analysis_pipeline.sh -p gisaid -n name_of_project -s prep
```
