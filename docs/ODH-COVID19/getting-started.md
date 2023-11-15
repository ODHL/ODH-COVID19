### Initialization
Deployment of the analysis workflow (`-p sarscov2`) requires the initalization of the pipeline. This step will create the directory structure needed for the pipeline, will create log files for documentation and will copy the necessary manifests and config files to their appropriate locations for pipeline control.

1. Change working directory to the analysis pipeline directory
2. Run initialization

```
cd worflows/SARS_CoV_2_Workflow

bash run_analysis_pipeline.sh -p init -n name_of_project

```

### Configuration Files
After completion of the initialization step, configuration files may be edited according to the project. These include:

#### 1. PIPELINE Config
- Description: This configuration file controls all metadata associated with the project, as well as pipeline specific parameters. Within this configuration file software versions can be selected and batch size can be controlled. GISAID-related parameters (optional and required) are also included in this configuration file.
- Location: /name_of_project/logs/config/config_pipeline.yaml

#### 2. CECRET Config
- Description: This configuration file controls all the features associated with the CECRET workflow.
- Location: /name_of_project/logs/config/config_cecret.config

#### 3. MULTIQC Config
-  Description: This configuration file controls all the features associated with the MULTIQC report generated upon pipeline completion.
- Location: /name_of_project/logs/config/config_multiqc.yaml


## Configuration Files
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
   - Originating lab: Where sequence data have been generated
   - Address: Address of originating lab
   - Submitting lab: Where sequence data is being submitted to GISAID
   - Address: Address of submitting lab
   - Authors: a comma separated list of Authors with complete First followed by Last Name
- Optional:
   - Additional location information: Cruise Ship, Convention, Live animal market
   - Additional host information: Patient infected while traveling in …. 
   - Sampling Strategy: Sentinel surveillance (ILI), Sentinel surveillance (ARI), Sentinel surveillance (SARI), Non-sentinel-surveillance (hospital), Non-sentinel-surveillance (GP network), Longitudinal sampling on same patient(s), S gene dropout
   - Specimen source: Sputum, Alveolar lavage fluid, Oro-pharyngeal swab, Blood, Tracheal swab, Urine, Stool, Cloakal swab, Organ, Feces, Other
   - Assembly method: CLC Genomics Workbench 12, Geneious 10.2.4, SPAdes/MEGAHIT v1.2.9, UGENE v. 33, etc.
   - Coverage: 70x, 1,000x, 10,000x (average)

## Software
### GISAID specific features
GISAID CLI requires authentication. Authentication must be performed every 100 days. 

To run tests, use client_id:
--client_id: TEST-EA76875B00C3

For sample uploads, use client_id obtained by emailing:
--email: clisupport@gisaid.org

User specific ID list
--cliend_id: cid-1e895d886d3a6

```
# Example test authentication
cli2 authenticate --client_id TEST-EA76875B00C3 --username sevillas2

# Example full authentication
cli2 authenticate --cliend_id [insert id] --username [username]
```