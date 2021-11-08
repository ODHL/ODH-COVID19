# ODH-COVID19
Ohio COVID project

# Workflow
1. Update config file
2. Create list of files to be uploaded
3. Review FASTA files and determine N content
4. Create metadata template
5. Create merged FASTA file
6. Upload to GISAID

# Directory Structure
## Before processing
- project_dir
-- fasta1.fasta
-- fasta2.fasta
-- fasta3.fasta
-- original_metadata.csv


## After processing
- project_dir
-- fasta1.fasta
-- fasta2.fasta
-- fasta3.fasta
-- original_metadata.csv
-- config.yaml

-- /timestamp
---- /merged_fastas
------ fasta[#].fasta (which were merged, seq name changed)
------ original_metadata.csv

---- /failedqc
------fasta[#].fasta (which failed qc)

---- passed_qc.txt
---- failed_qc.txt
---- batched_metadata.csv
---- batched_fasta.fasta
