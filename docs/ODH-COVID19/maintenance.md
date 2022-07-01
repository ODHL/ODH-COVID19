
 
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
