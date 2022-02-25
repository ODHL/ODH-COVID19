#!/bin/bash


#############################################################################################
# Background documentation
#############################################################################################
# Basespace
# https://developer.basespace.illumina.com/docs/content/documentation/cli/cli-examples#Downloadallrundata

#Docker location
# https://hub.docker.com/u/staphb

#CECRET GitHub location
# https://github.com/UPHL-BioNGS/Cecret

#############################################################################################
# functions
#############################################################################################

helpFunction()
{
   echo ""
   echo "Usage: $1 -p pipeline options"
   echo -e "\t-p options: run, init, update"
   echo "Usage: $2 -n project_name"
   echo -e "\t-n project name"
   echo "Usage: $3 -d download_arg"
   echo -e "\t-d Y flag to download DRAGEN analysis files"
   echo "Usage: $4 -t testing_arg"
   echo -e "\t-t Y flag indicate if run is a test"
   exit 1 # Exit script after printing help
}

while getopts "p:n:d:t:" opt
do
   case "$opt" in 
	p) pipeline="$OPTARG" ;;
     	n ) project_name="$OPTARG" ;;
      	d ) download_arg="$OPTARG" ;;
	t ) testing_arg="$OPTARG" ;;
      	? ) helpFunction ;; # Print helpFunction in case parameter is non-existent
   esac
done

# Print helpFunction in case parameters are empty
if [ -z "$pipeline" ] || [ -z $project_name ]; then
   echo "Some or all of the parameters are empty";
   helpFunction
fi

check_initialization(){
  if [[ ! -d $log_dir ]] || [[ ! -f "${log_dir}/pipeline_config.yaml" ]]; then
    echo "ERROR: You must initalize the dir before beginning pipeline"
    exit 1
  fi
}

#############################################################################################
# Config
#############################################################################################
#set args
if [ -z "$download_arg" ]; then download_arg="Y"; fi

#remove trailing / on directories
output_dir="../$project_name"
output_dir=$(echo $output_dir | sed 's:/*$::')

#set dirs
log_dir=$output_dir/logs
fastq_dir=$output_dir/fastq
cecret_dir=$output_dir/cecret

qc_dir=$output_dir/qc
qcreport_dir=$qc_dir/covid19_qcreport

tmp_dir=$output_dir/tmp
fastqc_dir=$tmp_dir/fastqc

analysis_dir=$output_dir/analysis
fasta_dir=$analysis_dir/fasta
ivar_dir=$analysis_dir/ivar
intermed_dir=$analysis_dir/intermed

#set files
sample_id_file=$log_dir/sample_ids.txt
pipeline_log=$log_dir/pipeline_log.txt

#set configs
multiqc_config="$log_dir/multiqc_config.yaml"
pipeline_config="$log_dir/pipeline_config.yaml"
cecret_config="22-02-23_cecret.config"


#############################################################################################
# Run CECRET
#############################################################################################
if [[ "$pipeline" == "init" ]]; then
	
	echo
	echo "*** INITIALIZING PIPELINE ***"

	#make directories, logs
        if [[ ! -d $output_dir ]]; then mkdir $output_dir; fi

        ##parent
        dir_list=(logs fastq cecret qc tmp analysis)
        for pd in "${dir_list[@]}"; do if [[ ! -d $output_dir/$pd ]]; then mkdir -p $output_dir/$pd; fi done

        ##qc
        dir_list=(covid19_qcreport)
        for pd in "${dir_list[@]}"; do if [[ ! -d $qc_dir/$pd ]]; then mkdir -p $qc_dir/$pd; fi done

        ##tmp
        dir_list=(fastqc unzipped)
        for pd in "${dir_list[@]}"; do if [[ ! -d $tmp_dir/$pd ]]; then mkdir -p $tmp_dir/$pd; fi done

        ##analysis
        dir_list=(fasta ivar intermed)
        for pd in "${dir_list[@]}"; do if [[ ! -d $analysis_dir/$pd ]]; then mkdir -p $analysis_dir/$pd; fi done

        ##make files
        touch $pipeline_log

	# copy config inputs to edit if doesn't exit
	files_save=("config/pipeline_config.yaml" "config/$cecret_config" "config/multiqc_config.yaml")

  	for f in ${files_save[@]}; do
        	IFS='/' read -r -a strarr <<< "$f"
        	if [[ ! -f "${log_dir}/${strarr[1]}" ]]; then
                	cp $f "${log_dir}/${strarr[1]}"
        	else
			echo
                	echo "Configs are already in output dir"
			echo
        	fi
  	done

	#output complete
	echo
  	echo -e "Configs are ready to be edited:\n${log_dir}"
	echo
	echo "*** INITIALIZATION COMPLETE ***"
	echo

elif [[ "$pipeline" == "update" ]]; then

        #update the staphb toolkit
        staphb-wf --auto_update

elif [[ "$pipeline" == "run" ]]; then
	
	#set args
	batch_limit=$(cat "${pipeline_config}" | grep "batch_limit: " | sed 's/batch_limit: //' | sed 's/"//g')
	date_stamp=$(cat "${pipeline_config}" | grep "seq_date: " | sed 's/seq_date: //' | sed 's/"//g')
	pangolin_version=$(cat "${pipeline_config}" | grep "pangolin_version: " | sed 's/pangolin_version: //' | sed 's/"//g')
	final_results=$analysis_dir/final_results_$date_stamp.csv
	
	#check initialization was completed
	check_initialization
	
	# specify version of panoglin in cecret config
        sed -i "s/pangolin_container = 'staphb\/pangolin:latest'/pangolin_container = 'staphb\/pangolin:$pangolin_version'/" $log_dir/$cecret_config

	#log
	echo "------------------------------------------------------------------------" >> $pipeline_log
	echo "*** CONFIG INFORMATION ***" >> $pipeline_log
	echo "Sequence run date: $date_stamp" >> $pipeline_log
	echo "Analysis date:" `date` >> $pipeline_log
	echo "Cecret config: $cecret_config" >> $pipeline_log
	echo "Pangolin version: $pangolin_version" >> $pipeline_log
	cat "$log_dir/$cecret_config" | grep "params.reference_genome" >> $pipeline_log
        cat "$log_dir/$cecret_config" | grep "params.gff_file" >> $pipeline_log
        #cat "$log_dir/$cecret_config" | grep "params.primer_set" >> $pipeline_log
        cat "$log_dir/$cecret_config" | grep "params.primer_bed" >> $pipeline_log
        cat "$log_dir/$cecret_config" | grep "params.amplicon_bed" >> $pipeline_log
        echo "------------------------------------------------------------------------" >> $pipeline_log

	echo
	echo "*** STARTING PIPELINE ***"
	echo "*** STARTING PIPELINE ***" >> $pipeline_log
	echo "Starting time: `date`" >> $pipeline_log
	echo "Starting space: `df . | sed -n '2 p' | awk '{print $5}'`" >> $pipeline_log
	#############################################################################################
	# Project Downloads
	#############################################################################################	
	#get project id
	project_id=`bs list projects --filter-term="$project_name" | sed -n '4 p' | awk '{split($0,a,"|"); print a[3]}' | sed 's/ //g'`

	#download the necessary project analysis files
	if [[ $download_arg == "Y" ]]; then
		echo "--Downloading analysis files"
		echo "--Downloading analysis files" >> $pipeline_log
		echo "---Starting time: `date`" >> $pipeline_log

		bs download project -i $project_id -o "$tmp_dir" --extension=zip
		
		echo "---Ending time: `date`" >> $pipeline_log
                echo "---Ending space: `df . | sed -n '2 p' | awk '{print $5}'`" >> $pipeline_log
	fi

	#############################################################################################
	# Batching
	#############################################################################################
	#create sample_id file - grab all files in dir, split by _, exclude OH- and noro- file names
	ls $tmp_dir | cut -f1 -d "_" | grep "202[0-9]." | grep -v "OH.*" | grep -v "noro.*" > $sample_id_file

	#read in text file with all project id's
	IFS=$'\n' read -d '' -r -a sample_list < $sample_id_file
	
	#break project into batches of N = batch_limit set above, create manifests for each
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

	# set testing parameter to only run 2 batches
	if [[ "$testing_arg" = "Y" ]]; then batch_count=2; fi
       
	#log
        # print number of lines in file without file name "<"
        sample_number=`wc -l < $sample_id_file`
        echo "--A total of $sample_number samples will be processed in $batch_count batches, with a maximum of $batch_limit per batch"
        echo "--A total of $sample_number samples will be processed in $batch_count batches, with a maximum of $batch_limit per batch" >> $pipeline_log

	#merge all batched outputs
        merged_samples=$log_dir/completed_samples.txt
        merged_cecret=$log_dir/cecret_results.txt
        merged_nextclade=$tmp_dir/nextclade_results.csv
        merged_pangolin=$tmp_dir/lineage_report.csv
        merged_summary=$analysis_dir/cecret_summary.csv
        merged_fragment=$intermed_dir/fragement_length.txt

	touch $merged_samples
        touch $merged_cecret
        touch $merged_nextclade
        touch $merged_pangolin
        touch $merged_summary
	touch $merged_fragment

	#############################################################################################
	# Analysis
	#############################################################################################
	#log
	echo "--Processing batches:"
	echo "--Processing batches:" >> $pipeline_log

	#for each batch
	for (( batch_id=1; batch_id<=$batch_count; batch_id++ )); do
	
		#set manifest
		batch_manifest=$log_dir/batch_0$batch_id.txt

		#make batch dirs
		fastq_batch_dir=$fastq_dir/batch_$batch_id
		cecret_batch_dir=$cecret_dir/batch_$batch_id
		if [[ ! -d $fastq_batch_dir ]]; then mkdir $fastq_batch_dir; fi
		if [[ ! -d $cecret_batch_dir ]]; then mkdir $cecret_batch_dir; fi

		#read text file
		IFS=$'\n' read -d '' -r -a sample_list < $batch_manifest

		#log
		# print number of lines in file without file name "<"
		n_samples=`wc -l < $batch_manifest`
		echo "----Batch_$batch_id ($n_samples samples)"
		echo "----Batch_$batch_id ($n_samples samples)" >> $pipeline_log


		#run per sample
		for sample_id in ${sample_list[@]}; do
		
			#download fastq files
			bs download biosample -n "$sample_id" -o $fastq_dir

        	        #make sample tmp_dir: tmp_dir/sample_id
	                if [[ ! -d "$tmp_dir/${sample_id}" ]]; then mkdir $tmp_dir/${sample_id}; fi

                	#unzip analysis file downloaded from DRAGEN to sample tmp dir - used in QC
                	unzip -o -q $tmp_dir/${sample_id}_[0-9]*/*_all_output_files.zip -d $tmp_dir/${sample_id}

                	#move needed files to general tmp dir
			mv $tmp_dir/${sample_id}/ma/* $tmp_dir/unzipped

			#move files to batch fasta dir
			mv $fastq_dir/${sample_id}*/*fastq.gz $fastq_batch_dir

                        #remove sample tmp dir, downloaded proj dir
                        rm -r --force $tmp_dir/${sample_id}
			rm -r --force $tmp_dir/${sample_id}_[0-9]*/*_all_output_files.zip
        	done

		#log
		echo "------CECRET"
		echo "------CECRET" >> $pipeline_log
		echo "-------Starting time: `date`" >> $pipeline_log
	        echo "-------Starting space: `df . | sed -n '2 p' | awk '{print $5}'`" >> $pipeline_log
	
		#run cecret
		staphb-wf cecret $fastq_batch_dir --reads_type paired --config $log_dir/$cecret_config --output $cecret_batch_dir

                echo "-------Ending time: `date`" >> $pipeline_log
		echo "-------Ending space: `df . | sed -n '2 p' | awk '{print $5}'`" >> $pipeline_log

		#############################################################################################
		# Clean-up
		#############################################################################################
		#add to master sample log
		cat $log_dir/batch_0$batch_id.txt >> $merged_samples
		
		#add to  master cecret results
		cat $cecret_batch_dir/cecret_results.txt >> $merged_cecret

		#add to master nextclade results
		cat $cecret_batch_dir/nextclade/nextclade.csv >> $merged_nextclade

		#add to master pangolin results
		cat $cecret_batch_dir/pangolin/lineage_report.csv >> $merged_pangolin

		#add to master cecret summary
		cat $cecret_batch_dir/summary/combined_summary.csv >> $merged_summary

                #create file of fragment lengths
                for f in $cecret_batch_dir/samtools_stats/aligned/*.stats.txt; do
                	frag_length=`cat $f | grep "average length" | awk '{print $4}'`
			file_name=`echo $f | rev | cut -f1 -d "/" | rev`
			file_name=${file_name%.stats*}
			echo -e "${file_name}\t${frag_length}\t${batch_id}" >> $merged_fragment
		done

		#mv all files to  master dirs
		mv $cecret_batch_dir/fastqc/* $fastqc_dir
		mv $cecret_batch_dir/consensus/* $fasta_dir
		mv $cecret_batch_dir/ivar_variants/* $ivar_dir

		#remove intermediate files
		sudo rm -r --force work
		sudo rm -r --force $cecret_batch_dir
		sudo rm -r --force $fastq_batch_dir
	done

	#############################################################################################
	# Create reports
	#############################################################################################
	#log
	echo "--Creating QC Report"
	echo "--Creating QC Report" >> $pipeline_log
	echo "---Starting time: `date`" >> $pipeline_log
        echo "---Starting space: `df . | sed -n '2 p' | awk '{print $5}'`" >> $pipeline_log

	#add config to qc dir
	sudo cp $multiqc_config $log_dir/multiqc_config.yaml

	#-d -dd 1 adds dir name to sample name
	multiqc -f -v \
        	-c $log_dir/multiqc_config.yaml \
        	$fastqc_dir \
        	$tmp_dir/unzipped \
        	-o $qcreport_dir

	#create final results file
	final_nextclade=$intermed_dir/final_nextclade.txt
	final_pangolin=$intermed_dir/final_pangolin.txt

	## remove duplicate headers
	#from pangolin: sampleid, pangolin status, lineage
	#from nextclade: sampleid, clade
	cat $merged_nextclade | sort | uniq -u | awk -F';' '{print $1,$2}'| awk '{ gsub(/Consensus_/,"",$1) gsub(/\.consensus_[a-z0-9._]*/,"",$1); print }'| awk '{ print $1","$2"_"$3 }' | awk '{ gsub(/"/,"",$2); print }' > $final_nextclade
	cat $merged_pangolin | sort | uniq -u |  awk -F',' '{print $1,$12,$2}'| awk '{ gsub(/Consensus_/,"",$1) gsub(/\.consensus_[a-z0-9._]*/,"",$1); print }' > $final_pangolin
	
	##pass to final results
	echo "sample_id pangolin_status pangolin_lineage nextclade_clade" > $final_results
	join <(sort $final_pangolin) <(sort $final_nextclade) -t $',' >> $final_results

	echo "---Ending time: `date`" >> $pipeline_log

	#create fragment plot
	python scripts/fragment_plots.py $merged_fragment $analysis_dir/fragment_plot.png
	
	#remove all proj files
	rm -r --force $tmp_dir
	rm -r --force $cecret

        #############################################################################################
	# Run GISAID UPLOAD
	#############################################################################################
	echo "--GISAID Upload"
	#bash gisaid.sh "${log_dir}" "${fasta_dir}"
	#"${log_dir}"/${date_stamp}_${project_id}_metadata.csv 2> "${log_dir}"/gisaid_warnings.txt

	#log
	echo "*** PIPELINE COMPLETE ***"
	echo "Ending time: `date`" >> $pipeline_log
	echo "Ending space: `df . | sed -n '2 p' | awk '{print $5}'`" >> $pipeline_log
	echo "*** PIPELINE COMPLETE ***" >> $pipeline_log
else
	echo "Pipeline options (-p) must be run, init or update"
fi

