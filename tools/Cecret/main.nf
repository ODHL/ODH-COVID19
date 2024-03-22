#!/usr/bin/env nextflow

//# For aesthetics - and, yes, we are aware that there are better ways to write this than a bunch of 'println' statements
println('') 
println('  ____ _____ ____ ____  _____ _____')
println(' / ___| ____/ ___|  _ \\| ____|_   _|')
println('| |   |  _|| |   | |_) |  _|   | |')
println('| |___| |__| |___|  _ <| |___  | |')
println(' \\____|_____\\____|_| \\_\\_____| |_|')

println('Version: ' + workflow.manifest.version)
println('')
println('Currently using the Cecret workflow for use with corresponding reference genome.\n')
println('Author: Erin Young')
println('email: eriny@utah.gov')
println('')

println('Cecret is named after a real lake!')
println('Visit https://www.alltrails.com/trail/us/utah/cecret-lake-trail to learn more.')
println('Not everyone can visit in person, so here is some ASCII art of nucleotides in lake forming a consensus sequence.')
println('             _________ ______')
println('        _ /      G    A   T   \\_____')
println('   __/    C      C A    G      T  C \\')
println(' /    G     A   T   T  A   G  G    T  \\_')
println('| G       G  C   A            G   T     \\')  
println(' \\      A     C     G   A   T    A  G  T  \\__')
println('  \\_           C       G    ____ _____ __ C  \\________')
println('     \\__T______ ___________/                \\ C T G A G G T C G A T A') 
println('                                                    A T G A C GTAGATA')
println('')

//# Starting the workflow --------------------------------------------------------------

nextflow.enable.dsl = 2

//# run params ---------------------------------------------------------------------
println('The files and directory for results is ' + params.outdir)
println('The species used to determine default variables and subworkflows is ' + params.species)

//# roughly grouping cp5u usage
println('The maximum number of CPUS used in this workflow is ' + params.maxcpus)

//# Adding in subworkflows
include { fasta_prep ; summary } from './modules/cecret.nf'      addParams(params)
include { cecret }               from './subworkflows/cecret.nf' addParams(params)
include { qc }                   from './subworkflows/qc'        addParams(params)
include { msa }                  from './subworkflows/msa'       addParams(params)
include { multiqc_combine }      from './modules/multiqc'        addParams(params)
include { mpx }                  from './subworkflows/mpx'       addParams(params)                                 
include { mpx as other }         from './subworkflows/mpx'       addParams(params)
include { sarscov2 }             from './subworkflows/sarscov2'  addParams(params)
include { test }                 from './subworkflows/test'      addParams(params) 

//# Now that everything is defined (phew!), the workflow can begin ---------------------------------------------------
//# getting input files
if ( params.sample_sheet ) { 
  Channel
    .fromPath(params.sample_sheet, type: 'file')
    .view { "Sample sheet found : ${it}" }
    .splitCsv( header: true, sep: ',' )
    .map { row -> tuple( "${row.sample}", [ file("${row.fastq_1}"), file("${row.fastq_2}") ]) }
    .branch {
      single     : it[1] =~ /single/
      multifasta : it[1] =~ /multifasta/
      fasta      : it[1] =~ /fasta/
      ont        : it[1] =~ /ont/       
      paired     : true 
    }
    .set { inputs }
  
  ch_paired_reads = inputs.paired.map{     it -> tuple(it[0], it[1],    'paired')}
  ch_single_reads = inputs.single.map{     it -> tuple(it[0], it[1][0], 'single')}
  ch_fastas       = inputs.fasta.map{      it -> tuple(it[0], it[1])}
  ch_multifastas  = inputs.multifasta.map{ it -> tuple(it[1])}
  ch_nanopore     = inputs.ont.map{        it -> tuple(it[0], it[1])}
} else {
  Channel
    .fromFilePairs(["${params.reads}/*_R{1,2}*.{fastq,fastq.gz,fq,fq.gz}",
                    "${params.reads}/*{1,2}*.{fastq,fastq.gz,fq,fq.gz}"], size: 2 )
    .unique()
    .map { reads -> tuple(reads[0].replaceAll(~/_S[0-9]+_L[0-9]+/,""), reads[1], 'paired' ) }
    .set { ch_paired_reads }

  Channel
    .fromPath("${params.single_reads}/*.{fastq,fastq.gz,fq,fq.gz}")
    .map { reads -> tuple(reads.simpleName, reads, 'single' ) }
    .set { ch_single_reads }

    Channel
    .fromPath("${params.nanopore}/*.{fastq,fastq.gz,fq,fq.gz}")
    .map { reads -> tuple(reads.simpleName, reads ) }
    .set { ch_nanopore }

  Channel
    .fromPath("${params.fastas}/*{.fa,.fasta,.fna}", type:'file')
    .map { fasta -> tuple(fasta.baseName, fasta ) }
    .set { ch_fastas }

  Channel
    .fromPath("${params.multifastas}/*{.fa,.fasta,.fna}", type:'file')
    .set { ch_multifastas }
}

ch_sra_accessions = Channel.from( params.sra_accessions )

//# Checking for input files and giving an explanatory message if none are found
ch_paired_reads
  .mix(ch_single_reads)
  .mix(ch_fastas)
  .mix(ch_multifastas)
  .mix(ch_sra_accessions)
  .mix(ch_nanopore)
  .ifEmpty{
    println('FATAL : No input files were found!')
    println("No paired-end fastq files were found at ${params.reads}. Set 'params.reads' to directory with paired-end reads")
    println("No single-end fastq files were found at ${params.single_reads}. Set 'params.single_reads' to directory with single-end reads")
    println("No fasta files were found at ${params.fastas}. Set 'params.fastas' to directory with fastas.")
    println("No multifasta files were found at ${params.multifastas}. Set 'params.multifastas' to directory with multifastas.")
    println("No sample sheet was fount at ${params.sample_sheet}. Set 'params.sample_sheet' to sample sheet file.")
    exit 1
}

//# getting a reference genome file
if (params.reference_genome){
  Channel
    .fromPath(params.reference_genome, type:'file')
    .ifEmpty{
      println("No reference genome was selected. Set with 'params.reference_genome'")
      exit 1
    }
    .set { ch_reference_genome }
} else {
  if ( params.species == 'sarscov2' ) {
    ch_reference_genome = Channel.fromPath(workflow.projectDir + '/genomes/MN908947.3.fasta', type: 'file')
  } else if ( params.species == 'mpx') {
    ch_reference_genome = Channel.fromPath(workflow.projectDir + '/genomes/NC_063383.1.fasta', type: 'file')
  } else {
    println("No reference genome was selected. Set with 'params.reference_genome'")
    println("Or set species to one with an included genome ('sarscov2' or 'mpx')")
    exit 1
    ch_reference_genome = Channel.empty()
  } 
}
ch_reference_genome.view { "Reference Genome : $it"}

//# getting the gff file for ivar variants
if ( params.ivar_variants ) {
  if (params.gff) {
    Channel
      .fromPath(params.gff, type:'file')
      .ifEmpty{
        println("No gff file was selected. Set with 'params.reference_genome'")
        exit 1
      }
      .set { ch_gff_file }
  } else {
    if ( params.species == 'sarscov2' ) {
      ch_gff_file = Channel.fromPath(workflow.projectDir + '/genomes/MN908947.3.gff', type: 'file')
    } else if ( params.species == 'mpx') {
      ch_gff_file = Channel.fromPath(workflow.projectDir + '/genomes/NC_063383.1.gff3', type: 'file')
    } else {
      println("No gff file was selected. Set with 'params.gff'")
      println("Or set 'params.species' to one with an included genome ('sarscov2' or 'mpx')")
      println("Or bypass this message completely by setting 'params.ivar_variants = False'")
      exit 1
      ch_gff_file = Channel.empty()
    } 
  }
} else {
  ch_gff_file = Channel.empty()
}
ch_gff_file.view { "GFF file : $it"}

//# channels of included files
included_primers     = [
  workflow.projectDir + '/schema/midnight_idt_V1_SARS-CoV-2.primer.bed',
  workflow.projectDir + '/schema/midnight_ont_V1_SARS-CoV-2.primer.bed',
  workflow.projectDir + '/schema/midnight_ont_V2_SARS-CoV-2.primer.bed',
  workflow.projectDir + '/schema/midnight_ont_V3_SARS-CoV-2.primer.bed',
  workflow.projectDir + '/schema/ncov_V3_nCoV-2019.primer.bed',
  workflow.projectDir + '/schema/ncov_V4_SARS-CoV-2.primer.bed',
  workflow.projectDir + '/schema/ncov_V4.1_SARS-CoV-2.primer.bed',
  workflow.projectDir + '/schema/ncov_V5.3.2_SARS-CoV-2.primer.bed',
  workflow.projectDir + '/schema/mpx_idt_primer.bed',
  workflow.projectDir + '/schema/mpx_primalseq_primer.bed'
  ]
included_amplicons = [
  workflow.projectDir + '/schema/midnight_idt_V1_SARS-CoV-2.insert.bed',
  workflow.projectDir + '/schema/midnight_ont_V1_SARS-CoV-2.insert.bed',
  workflow.projectDir + '/schema/midnight_ont_V2_SARS-CoV-2.insert.bed',
  workflow.projectDir + '/schema/midnight_ont_V3_SARS-CoV-2.insert.bed',
  workflow.projectDir + '/schema/ncov_V3_nCoV-2019.insert.bed',
  workflow.projectDir + '/schema/ncov_V4_SARS-CoV-2.insert.bed',
  workflow.projectDir + '/schema/ncov_V4.1_SARS-CoV-2.insert.bed',
  workflow.projectDir + '/schema/ncov_V5.3.2_SARS-CoV-2.insert.bed',
  workflow.projectDir + '/schema/mpx_idt_insert.bed',
  workflow.projectDir + '/schema/mpx_primalseq_insert.bed'
]

ch_primers                = Channel.fromPath(included_primers,   type: 'file')
ch_amplicons              = Channel.fromPath(included_amplicons, type: 'file')

available_primer_sets = [
  'midnight_idt_V1', 
  'midnight_ont_V1', 
  'midnight_ont_V2', 
  'midnight_ont_V3', 
  'ncov_V3', 
  'ncov_V4', 
  'ncov_V4.1', 
  'ncov_V5.3.2', 
  'mpx_primalseq', 
  'mpx_idt'
  ]

if ( params.trimmer != 'none' ) {
  //# Getting the primer file
  if (params.primer_bed) {
    Channel
      .fromPath(params.primer_bed, type:'file')
      .ifEmpty{
        println("A bedfile for primers is required. Set with 'params.primer_bed'.")
        exit 1
      }
      .set { ch_primer_bed } 
  } else if ( params.primer_set in available_primer_sets ) {
    Channel
      .fromPath( included_primers )
      .branch{ 
        match : it =~ /${params.primer_set}_*/
        }
      .first()
      .set { ch_primer_bed } 
  } else {
    println("No primers were found!")
    println("Set primer schema with 'params.primer_bed' or specify to 'none' if primers were not used")
    println("Or use included primer set by setting 'params.primer_set' to one of $available_primer_sets")
    exit 1
    ch_primer_bed = Channel.empty()
  }
  ch_primer_bed.view { "Primer BedFile : $it"}

  //# Getting the amplicon bedfile
  if ( params.aci ) {
    if (params.amplicon_bed) {
      Channel
        .fromPath(params.amplicon_bed, type:'file')
        .ifEmpty{
          println("A bedfile for amplicons is required. Set with 'params.amplicon_bed'.")
          println("Or set params.aci = False to skip this.")
          exit 1
        }
        .set { ch_amplicon_bed } 
    } else if ( params.primer_set in available_primer_sets ) {
      Channel
        .fromPath( included_amplicons )
        .branch{ 
          match : it =~ /${params.primer_set}_*/
          }
        .first()
        .set { ch_amplicon_bed } 
    } else {
      println("An amplicon bedfile wasn't found!")
      println("Set amplicon schema with 'params.amplicon_bed'")
      println("Or use included primer set by setting 'params.primer_set' to one of $available_primer_sets")
      println("Or set params.aci = False to skip this.")
      exit 1
      ch_amplicon_bed = Channel.empty()
    }
    ch_amplicon_bed.view { "Amplicon BedFile : $it"}
  } else {
    ch_amplicon_bed = Channel.empty()
  }
} else {
  ch_primer_bed   = Channel.empty()
  ch_amplicon_bed = Channel.empty()
}

//# scripts for legacy reasons
ch_combine_results_script = Channel.fromPath("${workflow.projectDir}/bin/combine_results.py",  type:'file')
ch_freyja_script          = Channel.fromPath("${workflow.projectDir}/bin/freyja_graphs.py",    type:'file')
ch_version_script         = Channel.fromPath("${workflow.projectDir}/bin/versions.py",         type:'file')

if ( params.kraken2_db ) {
  Channel
    .fromPath(params.kraken2_db, type:'dir')
    .view { "Kraken2 database : $it" }
    .set{ ch_kraken2_db }
} else {
  ch_kraken2_db = Channel.empty()
}

if ( ! params.download_nextclade_dataset ) {
  Channel
    .fromPath(params.predownloaded_nextclade_dataset)
    .ifEmpty{
      println("Dataset file could not be found at ${params.predownloaded_nextclade_dataset}.")
      println("Please set nextclade dataset file with 'params.predownloaded_nextclade_dataset'")
      exit 1
    }
    .set { ch_nextclade_dataset }
} else {
  ch_nextclade_dataset = Channel.empty()
}

ch_paired_reads
  .mix(ch_single_reads)
  .unique()
  .set { ch_reads }

ch_paired_reads.view { "Paired-end Fastq files found : ${it[0]}" }
ch_single_reads.view { "Fastq files found : ${it[0]}" }
ch_fastas.view       { "Fasta file found : ${it[0]}" }
ch_multifastas.view  { "MultiFasta file found : ${it}" }
ch_reads.ifEmpty     { println("No fastq or fastq.gz files were found at ${params.reads} or ${params.single_reads}") }

workflow CECRET {
    ch_for_dataset = Channel.empty()
    ch_for_version = Channel.from("Cecret version", workflow.manifest.version).collect()
    ch_prealigned  = Channel.empty()
    ch_versions    = Channel.empty()

    if ( ! params.sra_accessions.isEmpty() ) { 
      test(ch_sra_accessions)
      ch_reads = ch_reads.mix(test.out.reads)
    } 

    fasta_prep(ch_fastas)

    cecret(ch_reads, ch_nanopore, ch_reference_genome, ch_primer_bed)
    ch_versions = ch_versions.mix(cecret.out.versions)

    qc(ch_reads,
      cecret.out.clean_reads,
      ch_kraken2_db,
      cecret.out.sam,
      cecret.out.trim_bam,
      ch_reference_genome,
      ch_gff_file,
      ch_amplicon_bed,
      ch_primer_bed)

    ch_for_multiqc = cecret.out.for_multiqc.mix(qc.out.for_multiqc)
    ch_for_summary = qc.out.for_summary
    ch_versions    = ch_versions.mix(qc.out.versions)

    if ( params.species == 'sarscov2' ) {
      sarscov2(fasta_prep.out.fastas.mix(ch_multifastas).mix(cecret.out.consensus), cecret.out.trim_bam, ch_reference_genome, ch_nextclade_dataset, ch_freyja_script)
      
      ch_prealigned  = sarscov2.out.prealigned
      ch_for_multiqc = ch_for_multiqc.mix(sarscov2.out.for_multiqc)
      ch_for_dataset = sarscov2.out.dataset
      ch_for_summary = ch_for_summary.mix(sarscov2.out.for_summary)
      ch_versions    = ch_versions.mix(sarscov2.out.versions)
    
    } else if ( params.species == 'mpx') {
      mpx(fasta_prep.out.fastas.mix(ch_multifastas).mix(cecret.out.consensus), ch_nextclade_dataset)
      
      ch_for_multiqc = ch_for_multiqc.mix(mpx.out.for_multiqc)
      ch_for_dataset = mpx.out.dataset
      ch_for_summary = ch_for_summary.mix(mpx.out.for_summary)
      ch_prealigned  = mpx.out.prealigned
      ch_versions    = ch_versions.mix(mpx.out.versions)

    } else if ( params.species == 'other') {
      other(fasta_prep.out.fastas.concat(ch_multifastas).mix(cecret.out.consensus), ch_nextclade_dataset)
      
      ch_for_multiqc = ch_for_multiqc.mix(other.out.for_multiqc)
      ch_for_dataset = other.out.dataset
      ch_for_summary = ch_for_summary.mix(other.out.for_summary)
      ch_prealigned  = other.out.prealigned
      ch_versions    = ch_versions.mix(other.out.versions)

    } 

    if ( params.relatedness ) { 
      msa(fasta_prep.out.fastas.concat(ch_multifastas).concat(cecret.out.consensus), ch_reference_genome, ch_prealigned) 

      tree      = msa.out.tree
      alignment = msa.out.msa
      matrix    = msa.out.matrix

      ch_for_multiqc = ch_for_multiqc.mix(msa.out.for_multiqc)
      ch_versions    = ch_versions.mix(msa.out.versions)

    } else {
      tree      = Channel.empty()
      alignment = Channel.empty()
      matrix    = Channel.empty()
    }

    ch_versions
      .collectFile(
        keepHeader: false,
        name: "collated_versions.yml")
      .set { ch_collated_versions }

    multiqc_combine(ch_for_multiqc.mix(ch_collated_versions).collect(), ch_version_script)

    summary(
      ch_for_summary.mix(fasta_prep.out.fastas).mix(cecret.out.consensus).collect().map{it -> tuple([it])}
        .combine(ch_combine_results_script)
        .combine(ch_for_version.mix(cecret.out.for_version).collect().map{it -> tuple([it])})
        .combine(multiqc_combine.out.files.ifEmpty([]).map{it -> tuple([it])}))

  emit:
    bam       = cecret.out.trim_bam
    consensus = fasta_prep.out.fastas.mix(ch_multifastas).mix(cecret.out.consensus).collect()
    tree      = tree
    alignment = alignment
    matrix    = matrix
}

workflow {
  CECRET ()
}

workflow.onComplete {
  println("Pipeline completed at: $workflow.complete")
  println("A summary of results can be found in a comma-delimited file: ${params.outdir}/cecret_results.csv")
  println("A summary of results can be found in a tab-delimited file: ${params.outdir}/cecret_results.txt")
  println("Execution status: ${ workflow.success ? 'OK' : 'failed' }")
}
