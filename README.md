# ODH-COVID19
Ohio COVID project

## Workflow
1. Update config file
2. Create list of files to be uploaded
3. Review FASTA files and determine N content
4. Create metadata template
5. Create merged FASTA file
6. Upload to GISAID

## Directory Structure
### Before processing
- project_dir
  - fasta1.fasta
  - fasta2.fasta
  - fasta3.fasta
  - original_metadata.csv


### After processing
- project_dir
  - fasta1.fasta
  - fasta2.fasta
  - fasta3.fasta
  - original_metadata.csv
  - config.yaml

  - /timestamp
    - /merged_fastas
      - fasta[#].fasta (which were merged, seq name changed)
    - /failedqc
      - fasta[#].fasta (which failed qc)
    - passed_qc.txt
    - failed_qc.txt
    - batched_metadata.csv
    - batched_fasta.fasta

### Example outputs
#### Example failed_qc.txt
File will explain why the sample failed
```
#filename, reason for failure
/Users/sevillas2/Desktop/APHL/test_data/OH-123/2021063918_consensus.fasta	Missing metadata
/Users/sevillas2/Desktop/APHL/test_data/OH-123/seq2.fasta	Missing metadata
/Users/sevillas2/Desktop/APHL/test_data/OH-123/seq3.fasta 	 53% N
/Users/sevillas2/Desktop/APHL/test_data/OH-123/seq4.fasta 	 53% N
```

#### Example passed_qc.txt
```
#original header, reformatted header
>2021063920	2021063920
>something/goes/here_SC1234/2020	202011234
```
