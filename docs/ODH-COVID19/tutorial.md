
## Tutorial
Testing parameters have been created in order to test the settings of the pipeline with new data, or train new staff on it's usage. Test settings will download a complete project, but will only run two batches, with two samples in each batch. Initialization, run, and QC parameters should be reviewed below as they may be used in conjunction with the test setting.

1. Change working directory to the analysis pipeline directory
2. Run test on project name_of_project with the testing (-t) flag turned on (Y).(OPTIONAL) select whether a QC report (-q) should be generated (default "Y")

```
# 1. move to working dir
cd analysis_pipeline

# 2. run with testing flag on, without QC report
bash run_analysis_pipeline.sh -m test -n name_of_project -t Y -q N
```
