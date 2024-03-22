process download {
  tag        "${sra}"
  publishDir "${params.outdir}", mode: 'copy'
  container  'quay.io/biocontainers/pandas:1.5.2'
  label      "process_single"

  //#UPHLICA maxForks 10
  //#UPHLICA errorStrategy { task.attempt < 2 ? 'retry' : 'ignore'}
  //#UPHLICA pod annotation: 'scheduler.illumina.com/presetSize', value: 'standard-medium'
  //#UPHLICA memory 1.GB
  //#UPHLICA cpus 3
  //#UPHLICA time '45m'

  when:
  task.ext.when == null || task.ext.when

  input:
  val(sra)

  output:
  tuple val(sra), file("sra/paired/${sra}*fastq.gz"), val("paired"), optional: true, emit: paired
  tuple val(sra), file("sra/single/${sra}*fastq.gz"), val("single"), optional: true, emit: single

  shell:
  """
    mkdir -p sra/{paired,single}

    sra=${sra}

    wget ftp://ftp.sra.ebi.ac.uk/vol1/fastq/\${sra:0:6}/0\${sra: -2}/\${sra}/\${sra}_1.fastq.gz || \
        wget ftp://ftp.sra.ebi.ac.uk/vol1/fastq/\${sra:0:6}/0\${sra: -2}/\${sra}/\${sra}.fastq.gz

    if [ -f "\${sra}_1.fastq.gz" ]
    then
        wget ftp://ftp.sra.ebi.ac.uk/vol1/fastq/\${sra:0:6}/0\${sra: -2 }/\${sra}/\${sra}_2.fastq.gz
        mv \${sra}_*.fastq.gz sra/paired/.
    elif [ -f "\${sra}.fastq.gz" ]
    then
        mv \${sra}.fastq.gz sra/single/.
    else
        echo "Could not download file for SRA accession ${sra}"
    fi
  """
}

//# some fastas are created with the header of >reference, so this changes the header
process fasta_prep {
  tag        "${fasta}"
  //# nothing to publish in publishDir
  container  'quay.io/biocontainers/pandas:1.5.2'
  label      "process_single"

  //#UPHLICA maxForks 10
  //#UPHLICA errorStrategy { task.attempt < 2 ? 'retry' : 'ignore'}
  //#UPHLICA pod annotation: 'scheduler.illumina.com/presetSize', value: 'standard-medium'
  //#UPHLICA memory 1.GB
  //#UPHLICA cpus 3
  //#UPHLICA time '45m'

  when:
  fasta != null && (task.ext.when == null || task.ext.when)

  input:
  tuple val(sample), file(fasta)

  output:
  path "fasta_prep/${fasta}", optional: true, emit: fastas

  shell:
  def prefix = task.ext.prefix ?: "${sample}"
  """
  mkdir -p fasta_prep

  echo ">${prefix}" > fasta_prep/${fasta}
  grep -v ">" ${fasta} | fold -w 75 >> fasta_prep/${fasta}
  """
}

process summary {
  tag        "Creating summary files"
  label      "process_single"
  publishDir path: params.outdir, mode: 'copy'
  container  'quay.io/biocontainers/pandas:1.5.2'

  //#UPHLICA maxForks 10
  //#UPHLICA errorStrategy { task.attempt < 2 ? 'retry' : 'ignore'}
  //#UPHLICA pod annotation: 'scheduler.illumina.com/presetSize', value: 'standard-medium'
  //#UPHLICA memory 1.GB
  //#UPHLICA cpus 3
  //#UPHLICA time '45m'

  when:
  task.ext.when == null || task.ext.when

  input:
  tuple file(files), file(script), val(versions), file(multiqc)

  output:
  path "cecret_results.{csv,txt}", emit: summary_file

  shell:
  def multiqc_files = multiqc.join(" ")
  """
    echo "${versions}" | cut -f 1,3,5,7,9,11  -d ',' | sed 's/\\[//g' | sed 's/\\]//g' | sed 's/, /,/g' >  versions.csv
    echo "${versions}" | cut -f 2,4,6,8,10,12 -d ',' | sed 's/\\[//g' | sed 's/\\]//g' | sed 's/, /,/g' | awk '{(\$1=\$1); print \$0}' >> versions.csv

    echo "Summary files are ${files}"

    mkdir multiqc_data
    for file in ${multiqc_files}
    do
      if [ -f "\$file" ]; then mv \$file multiqc_data/. ; fi
    done

    cat *_ampliconstats.txt | grep -h ^FREADS > ampliconstats.summary
    
    if [ -s "vadr.vadr.sqa" ] ; then tail -n +2 "vadr.vadr.sqa" | grep -v "#-" | tr -s '[:blank:]' ',' > vadr.csv ; fi

    python ${script} ${params.minimum_depth}
  """
}

process unzip {
  tag        "unzipping nextclade dataset"
  label      "process_single"
  //# nothing to publish in publishDir
  container  'quay.io/biocontainers/pandas:1.5.2'

  //#UPHLICA maxForks 10
  //#UPHLICA errorStrategy { task.attempt < 2 ? 'retry' : 'ignore'}
  //#UPHLICA pod annotation: 'scheduler.illumina.com/presetSize', value: 'standard-medium'
  //#UPHLICA memory 1.GB
  //#UPHLICA cpus 3
  //#UPHLICA time '45m'

  when:
  params.nextclade && (task.ext.when == null || task.ext.when)

  input:
  file(input)

  output:
  path "dataset", emit: dataset

  shell:
  """
  mkdir dataset
  unzip ${input} -d dataset
  """
}
