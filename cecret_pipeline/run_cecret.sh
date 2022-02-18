#!/bin/bash

helpFunction()
{
   echo ""
   echo "Usage: $1 -p pipeline options"
   echo -e "\t-p options: run"
   echo "Usage: $2 -n projet_name"
   echo -e "\t-n project name"
   echo "Usage: $3 -o output_dir"
   echo -e "\t-o path to output directory"
   echo "Usage: $4 -d download_arg"
   echo -e "\t-d Y flag to download files"
   exit 1 # Exit script after printing help
}

while getopts "p:n:o:d:" opt
do
   case "$opt" in
      p ) pipeline="$OPTARG" ;;
      n ) project_name="$OPTARG" ;;
      o ) output_dir="$OPTARG" ;;
      d ) download_arg="$OPTARG" ;;
      ? ) helpFunction ;; # Print helpFunction in case parameter is non-existent
   esac
done

# Print helpFunction in case parameters are empty
if [ -z "$pipeline" ] || [ -z $project_name ] || [ -z "$output_dir" ]; then
   echo "Some or all of the parameters are empty";
   helpFunction
fi

#set args
batch_limit=2

#set dirs
log_dir=$output_dir/logs
analysis_dir=$output_dir/analysis
fastq_dir=$output_dir/fastq
tmp_dir=$output_dir/tmp

qc_dir=$output_dir/qc
qcreport_dir=$qc_dir/covid19_qcreport

cecret_dir=$output_dir/cecret

fastqc_dir=$tmp_dir/fastqc
fasta_dir=$analysis_dir/fasta
ivar_dir=$analysis_dir/ivar

#make dirs as needed
if [[ ! -d $log_dir ]]; then mkdir $log_dir; fi
if [[ ! -d $analysis_dir ]]; then mkdir $analysis_dir; fi
if [[ ! -d $fastq_dir ]]; then mkdir $fastq_dir; fi
if [[ ! -d $qc_dir ]]; then mkdir $qc_dir; fi
if [[ ! -d $tmp_dir/unzipped ]]; then mkdir -p $tmp_dir/unzipped; fi
if [[ ! -d $tmp_dir/samtools ]]; then mkdir -p $tmp_dir/samtools; fi
if [[ ! -d $cecret_dir ]]; then mkdir $cecret_dir; fi
if [[ ! -d $fastqc_dir ]]; then mkdir $fastqc_dir; fi 
if [[ ! -d $fasta_dir ]]; then mkdir $fasta_dir; fi
if [[ ! -d $ivar_dir ]]; then mkdir $ivar_dir; fi

#set configs
cecret_config=config/22-02-11_cecret.config
multiqc_config=config/multiqc_config.yaml

#set files
sample_id_file=$log_dir/sample_ids.txt
pipeline_log=$log_dir/pipeline_log.txt
touch $pipeline_log

## Run CECRET pipeline
if [[ "$pipeline" == "run" ]]; then
	echo "*** STARTING PIPELINE ***"
	
	#log info
	echo "*** STARTING PIPELINE ***" >> $pipeline_log
	echo "Starting time: `date`" >> $pipeline_log
	
	#get project id
	project_id=`bs list projects --filter-term="$project_name" | sed -n '4 p' | awk '{split($0,a,"|"); print a[3]}' | sed 's/ //g'`

	#download the necessary project analysis files
	if [[ $download_arg == "Y" ]]; then
		echo "--Downloading analysis files"
		echo "--Downloading analysis files" >> $pipeline_log
		echo "---Starting time: `date`" >> $pipeline_log

		#bs download project -i $project_id -o "$tmp_dir" --extension=zip
		
		echo "---Ending time: `date`" >> $pipeline_log
	fi
	
	#create sample_id file
	ls $tmp_dir | cut -f1 -d "_" | grep "202[0-9]." > $sample_id_file

	#read in text file with all project id's
	IFS=$'\n' read -d '' -r -a sample_list < $sample_id_file
	
	#break project into batches of 50, create manifests for each
	sample_count=1
	batch_count=0
	
	#for each sample, split into batches
	echo "--Creating batch files"
	for sample_id in ${sample_list[@]}; do
		
		#if the sample count is 1 then create new batch
		if [[ "$sample_count" -eq 1 ]]; then
			batch_count=$((batch_count+1))
			
			#remove previous versions of batch log
			batch_manifest=$log_dir/batch_0$batch_count.txt
			if [[ -f $batch_manifest ]]; then rm $batch_manifest; fi
			
			#create batch manifest
			touch $log_dir/batch_0$batch_count.txt
		fi
		
		#set batch manifest
		batch_manifest=$log_dir/batch_0$batch_count.txt
		
		#echo sample id to the batch
		echo ${sample_id} >> $batch_manifest
		
		#increase sample counter
		((sample_count+=1))
		
		#reset counter when equal to batch_limit
		if [[ "$sample_count" -gt "$batch_limit" ]]; then
			sample_count=1
		fi
	done

	#for each batch
	echo "--Processing batches:"
	echo "--Processing batches:" >> $pipeline_log

	#for (( batch_id=1; batch_id<=$batch_count; batch_id++ )); do
	for (( batch_id=1; batch_id<=1; batch_id++ )); do
	
		echo "----batch_$batch_id"
		echo "----batch_$batch_id" >> $pipeline_log
	
		#set manifest
		batch_manifest=$log_dir/batch_0$batch_id.txt

		#make batch dirs
		fastq_batch_dir=$fastq_dir/batch_$batch_id
		cecret_batch_dir=$cecret_dir/batch_$batch_id
		if [[ ! -d $fastq_batch_dir ]]; then mkdir $fastq_batch_dir; fi
		if [[ ! -d $cecret_batch_dir ]]; then mkdir $cecret_batch_dir; fi

		#read text file
		IFS=$'\n' read -d '' -r -a sample_list < $batch_manifest

		#echo if downloading
                if [[ $download_arg == "Y" ]]; then echo "------downloading fastq files"; fi

		#run per sample
		for sample_id in ${sample_list[@]}; do
		
			#download fiies
			if [[ $download_arg == "Y" ]]; then 
				bs download biosample -n "$sample_id" -o $fastq_dir
			fi

        	        #make sample tmp_dir
	                if [[ ! -d "$tmp_dir/${sample_id}" ]]; then mkdir $tmp_dir/${sample_id}; fi

                	#unzip analysis file to sample tmp dir
                	unzip -o -q $tmp_dir/${sample_id}_[0-9]*/*_all_output_files.zip -d $tmp_dir/${sample_id}

                	#move needed files to general tmp dir
                	#todo
			sudo cp $tmp_dir/${sample_id}/ma/* $tmp_dir/unzipped

                	#remove sample tmp dir
                	rm -r --force $tmp_dir/${sample_id}

			#move files to batch fasta dir
			#todo
			sudo cp $fastq_dir/${sample_id}*/*fastq.gz $fastq_batch_dir
        	done


		#run cecret
		echo "------starting cecret"
		echo "------starting cecret" >> $pipeline_log
		echo "-------starting time: `date`" >> $pipeline_log

		sudo cp $cecret_config $log_dir/cecret_config.config
		staphb-wf cecret $fastq_batch_dir --reads_type paired --config $log_dir/cecret_config.config --output $cecret_batch_dir

                echo "-------ending time: `date`" >> $pipeline_log
		
		#remove intermediate files
		sudo rm -r --force work
	done
	echo "---ending time: `date`" >> $pipeline_log

	#merge all batched outputs
       	merged_samples=$log_dir/completed_samples.txt
	merged_cecret=$log_dir/cecret_results.txt
	merged_nextclade=$analysis_dir/nextclade_results.csv
	merged_pangolin=$analysis_dir/lineage_report.csv
	merged_summary=$analysis_dir/cecret_summary.csv

	touch $merged_samples
	touch $merged_cecret
	touch $merged_nextclade
	touch $merged_pangolin
	touch $merged_summary

	for (( batch_id=1; batch_id<=1; batch_id++ )); do
		batch_dir=$cecret_dir/batch_$batch_id

		#add to master sample log
		cat $log_dir/batch_0$batch_id.txt >> $merged_samples
		
		#add to  master cecret results
		cat $batch_dir/cecret_results.txt >> $merged_cecret

		#add to master nextclade results
		cat $batch_dir/nextclade/nextclade.csv >> $merged_nextclade

		#add to master pangolin results
		cat $batch_dir/pangolin/lineage_report.csv >> $merged_pangolin

		#add to master cecret summary
		cat $batch_dir/summary/combined_summary.csv >> $merged_summary

		#create master dirs
		mv $batch_dir/fastqc/* $fastqc_dir
		mv $batch_dir/consensus/* $fasta_dir
		mv $batch_dir/ivar_variants/* $ivar_dir

		#move samtools files for QC analysis
		mv $batch_dir/samtools_coverage/aligned* $tmp_dir/samtools
	done

	#create QC Report
	echo "--Creating QC Report"
	echo "--Creating QC Report" >> $pipeline_log

	#add config to qc dir
	sudo cp $multiqc_config $log_dir/multiqc_config.yaml

	#-d -dd 1 adds dir name to sample name
	echo "---starting time: `date`" >> $pipeline_log
	multiqc -f -v \
        	-c $log_dir/multiqc_config.yaml \
        	$fastqc_dir \
        	$tmp_dir/unzipped \
		$tmp_dir/samtools \
        	-o $qcreport_dir
	echo "---ending time: `date`" >> $pipeline_log

	#remove all unneded files
	#rm -r --force $tmp_dir
	#rm -r --force $cecret

	#complete log file
	echo "***COMPLETED PIPELINE"
	echo "ending time: `date`" >> $pipeline_log
fi

