# Dependencies
## Nextflow [Required]
- [Nextflow](https://www.nextflow.io/docs/latest/getstarted.html)

## Singularity OR Docker [sarscov2 ONLY]
Either can be deployed within the `nextflow.config` file by setting the profile as singularity or docker during runtime
- [Singularity](https://singularity.lbl.gov/install-linux) or [Docker](https://docs.docker.com/get-docker/) 

## Basespace [sarscov2 ONLY]
To access the sequencing files, the `basespace cli` must be installed.
-[Basespace](https://developer.basespace.illumina.com/docs/content/documentation/cli/cli-overview)

## GISAID [gisaid ONLY]
To upload to GISAID, the `gisaid cli` must be installed. Prior to use the GISAID CLI requires authentication. Authentication must be performed every 100 days. 

```
# Example test authentication
cli2 authenticate --client_id TEST-EA76875B00C3 --username sevillas2

# Example full authentication
cli2 authenticate --cliend_id [insert id] --username [username]
```

## Python
Python3 is required to run quality control report scripts.

## R
R version 4.3 is require to run analytical report scripts.