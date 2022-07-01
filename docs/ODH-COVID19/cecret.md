### Running CECRET workflow

0. Ensure initialization has been complete
1. Change working directory to the analysis pipeline directory
2. Select the run flag (-r run) on the project (-n name_of_project). (OPTIONAL) select whether a QC report (-q) should be generated (default "Y")

```
# 1. move to working dir
cd analysis_pipeline

# 2A. run with QC report
bash run_analysis_pipeline.sh -m cecret -n name_of_project -q Y

# 2B. run without QC report
bash run_analysis_pipeline.sh -m cecret -n name_of_project -q N

```