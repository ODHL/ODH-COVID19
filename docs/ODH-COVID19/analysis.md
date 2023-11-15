### Running Analysis workflow

0. Initialization has been complete (see Getting Started for details)
1. Change working directory to the analysis pipeline directory
2. Run analysis workflow

```
# 1
cd worflows/SARS_CoV_2_Workflow

# 2A run entire pipeline
bash run_analysis_pipeline.sh -p sarscov2 -n name_of_project

# 2B. run only download
bash run_analysis_pipeline.sh -p sarscov2 -n name_of_project -s DOWNLOAD
```