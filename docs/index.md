The ODHL SARS-COV2 pipeline should be deployed, as follows:

## Overview
The pipeline workflow is as follows:
- [Initialize](https://odhl.github.io/SARS_CoV_2_Workflow/ODH-COVID19/getting-started/#initialization)
- [SARSCOV2 Analysis](https://odhl.github.io/SARS_CoV_2_Workflow/ODH-COVID19/analysis/)
- [GISAID Upload](https://odhl.github.io/SARS_CoV_2_Workflow/ODH-COVID19/gisaid/)
- [NCBI Upload Preparation](https://odhl.github.io/SARS_CoV_2_Workflow/ODH-COVID19/ncbi/)

## Usage
1. Change working directory to the analysis pipeline directory
2. Initialize the pipeline
3. Run `sarscov2` analysis workflow
4. Add metadata manifest to `/name_of_project/logs/manifests` dir
5. Run `gisaid` workflow
6. Move `/name_of_project/` dir to the L:Drive
7. Run `ncbi` workflow; subworkflow `input`
8. Upload NCBI files to NCBI offline
9. Add NCBI upload results files to `/name_of_project/logs/ncbi` dir
10. Run `ncbi` workflow; subworkflow `output`

```
#1 Change working directory to the analysis pipeline directory
cd SARS_CoV_2_Workflow

#2 Initialize the pipeline
bash run_analysis_pipeline.sh -p init -n name_of_project

#3  Run `sarscov2` analysis workflow
bash run_analysis_pipeline.sh -p sarscov2 -n name_of_project -s ALL

#4 Add metadata manifest to `/name_of_project/logs/manifests` dir
# done via an SSH connection

#5  Run `gisaid` workflow
bash run_analysis_pipeline.sh -p gisaid -n name_of_project -s ALL

#6 Move `/name_of_project/` dir to the L:Drive
# done via an SSH connection

#7 Run `ncbi` workflow; subworkflow `input`
bash run_analysis_pipeline.sh -p ncbi -n name_of_project -s input

#8 Add NCBI files to L:Drive; Upload NCBI files to NCBI offline
# done via an SSH connection

#9 Add NCBI upload results files to `/name_of_project/logs/ncbi` dir
# done via an SSH connection

#10 Run `ncbi` workflow; subworkflow `output`
bash run_analysis_pipeline.sh -p ncbi -n name_of_project -s output
```