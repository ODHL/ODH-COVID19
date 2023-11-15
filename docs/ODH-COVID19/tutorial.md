
## Tutorial
Testing parameters have been created in order to test the settings of the pipeline with new data, or train new staff on it's usage. Test settings will download a complete project, but will only run two batches, with two samples in each batch. Initialization, run, and QC parameters should be reviewed below as they may be used in conjunction with the test setting.

1. Change working directory to the analysis pipeline directory
2. Run analysis workflow

```
# 1. move to working dir
cd worflows/SARS_CoV_2_Workflow

# 2. run test
bash run_analysis_pipeline.sh -p sarscov2 -n name_of_project -s ALL -t Y
```
