### Running NCBI workflow

0. `sarscov2` workflow has been completed (see Analysis for more details)
0. `gisaid` workflow has been completed (see GISAID for more details)
1. Change working directory to the analysis pipeline directory
2. Run analysis workflow

    - There are several subworkflows that are available to the user. These include: 

        - `INPUT`: 

            - Transforms passing samples metadata into NCBI required template(s) (NOTE: several batches may be created dependent on file size)
            - Transforms passing samples FASTA files into NCBI required FASTA (NOTE: several batches may be created dependent on file size)

        - `OUTPUT`: 

            - Merge NCBI ID's into final output report

```
#1 change to the working directory
cd SARS_CoV_2_Workflow

#2A run workflow command: ncbi; subworkflow INPUT
bash run_analysis_pipeline.sh -p gisaid -n name_of_project -s input

#2B run workflow command: sarscov2; subworkflow OUTPUT
bash run_analysis_pipeline.sh -p gisaid -n name_of_project -s output
```

