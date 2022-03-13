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
   echo -e "\t-p options: init, run, gisaid, update"
   echo "Usage: $2 -n project_name"
   echo -e "\t-n project name"
   echo "Usage: $3 -q qc_flag"
   echo -e "\t-q Y flag of whether to run QC analysis on files"
   echo "Usage: $4 -t testing_flag"
   echo -e "\t-t Y flag indicate if run is a test"
   exit 1 # Exit script after printing help
}

while getopts "p:n:q:t:" opt
do
   case "$opt" in 
	p) pipeline="$OPTARG" ;;
     	n ) project_name="$OPTARG" ;;
      	q ) qc_flag="$OPTARG" ;;
	t ) testing_flag="$OPTARG" ;;
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
if [ -z "$qc_flag" ]; then qc_flag="Y"; fi
if [ -z "$testing_flag" ]; then testing_flag="N"; fi

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
gisaid_dir=$fasta_dir/gisaid_not_uploaded

ivar_dir=$analysis_dir/ivar
intermed_dir=$analysis_dir/intermed

#set files
sample_id_file=$log_dir/sample_ids.txt
pipeline_log=$log_dir/pipeline_log.txt
fragement_plot=$qc_dir/fragment_plot.png
gisaid_log=$log_dir/gisaid_log.txt

#set configs
multiqc_config="$log_dir/multiqc_config.yaml"
pipeline_config="$log_dir/pipeline_config.yaml"

#default complete pipeline without qc flag, otherwise run abbreviated pipeline
if [[ "$qc_flag" == "Y" ]] ; then
	cecret_config="22-02-23_cecret.config"
else
	cecret_config="22-02-23_cecret_partial.config"
fi
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
        for pd in "${dir_list[@]}"; do if [[ ! -d $output_dir/$pd ]]; then mkdir -p $output_dir/$pd; fi; done

        ##qc
        dir_list=(covid19_qcreport)
        for pd in "${dir_list[@]}"; do if [[ ! -d $qc_dir/$pd ]]; then mkdir -p $qc_dir/$pd; fi; done

        ##tmp
        dir_list=(fastqc unzipped)
        for pd in "${dir_list[@]}"; do if [[ ! -d $tmp_dir/$pd ]]; then mkdir -p $tmp_dir/$pd; fi; done

        ##analysis
        dir_list=(fasta ivar intermed)
        for pd in "${dir_list[@]}"; do if [[ ! -d $analysis_dir/$pd ]]; then mkdir -p $analysis_dir/$pd; fi; done

	##gisaid
	dir_list=(gisaid_not_uploaded gisaid_complete gisaid_error)
        for pd in "${dir_list[@]}"; do if [[ ! -d $fasta_dir/$pd ]]; then mkdir -p $fasta_dir/$pd; fi; done

        ##make files
        touch $pipeline_log
	touch $gisaid_log

	# copy config inputs to edit if doesn't exit
	files_save=("config/pipeline_config.yaml" "config/$cecret_config" "config/multiqc_config.yaml")

  	for f in ${files_save[@]}; do
        	IFS='/' read -r -a strarr <<< "$f"
        	if [[ ! -f "${log_dir}/${strarr[1]}" ]]; then
                	cp $f "${log_dir}/${strarr[1]}"
        	fi
  	done

  	#output
	echo -e "Configs are ready to be edited:\n${log_dir}"
	echo "*** INITIALIZATION COMPLETE ***"
	echo

elif [[ "$pipeline" == "update" ]]; then

        #update the staphb toolkit
        staphb-wf --auto_update

elif [[ "$pipeline" == "run" ]]; then
	
	#set args
	batch_limit=$(cat "${pipeline_config}" | grep "batch_limit: " | sed 's/batch_limit: //' | sed 's/"//g')
	date_stamp=$(cat "${pipeline_config}" | grep "seq_date: " | sed 's/seq_date: //' | sed 's/"//g')
	pangolin_id=$(cat "${pipeline_config}" | grep "pangolin_version: " | sed 's/pangolin_version: //' | sed 's/"//g')
	final_results=$analysis_dir/final_results_$date_stamp.csv
	
	#Convert pangolin version, error if wrong value selected
	if [[ "$pangolin_id" == 18 ]]; then
		pangolin_version="3.1.18-pangolearn-2022-01-20"
	elif [[ "$pangolin_id" == 19 ]]; then
                pangolin_version="3.1.19-pangolearn-2022-01-20"
	elif [[ "$pangolin_id" == 20 ]]; then
                pangolin_version="3.1.20-pangolearn-2022-02-02"
	else
		echo "Choose the correct pangolin version in logs/pipeline_config.yaml"
		exit
	fi
	
	#check initialization was performed
	check_initialization

	# specify version of panoglin in cecret config
        old_cmd="pangolin_container = 'staphb\/pangolin:latest'"
        new_cmd="pangolin_container = 'staphb\/pangolin:$pangolin_version'"
        sed -i "s/$old_cmd/$new_cmd/" $log_dir/$cecret_config

        # Print pangolin version and cecret QC version
	echo
        echo "The pangolin version to be run:"
        cat $log_dir/$cecret_config | grep "staphb/pangolin:"
	echo
	echo "The following CECRET config will be used (partial or complete)"
	echo $cecret_config
	
	#log
	echo "------------------------------------------------------------------------" >> $pipeline_log
	echo "*** CONFIG INFORMATION ***" >> $pipeline_log
	echo "Sequence run date: $date_stamp" >> $pipeline_log
	echo "Analysis date:" `date` >> $pipeline_log
	echo "Cecret config: $cecret_config" >> $pipeline_log
	echo "Pangolin version: $pangolin_version" >> $pipeline_log
	cat "$log_dir/$cecret_config" | grep "params.reference_genome" >> $pipeline_log
        cat "$log_dir/$cecret_config" | grep "params.gff_file" >> $pipeline_log
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

	#if a QC report is to be created (qc_flag=Y) then download the necessary project analysis files
	#if it is not needed, then download smaller json files to determine all sample ids in project
	if [[ "$qc_flag" == "Y" ]]; then
		echo "--Downloading analysis files (this may take a few minutes to begin)"
		echo "--Downloading analysis files" >> $pipeline_log
		echo "---Starting time: `date`" >> $pipeline_log

		bs download project -i $project_id -o "$tmp_dir" --extension=zip
		
		echo "---Ending time: `date`" >> $pipeline_log
                echo "---Ending space: `df . | sed -n '2 p' | awk '{print $5}'`" >> $pipeline_log
	else
		echo "--Downloading sample list (this may take a few minutes to begin)"
		echo "--Downloading sample list" >> $pipeline_log
		echo "---Starting time: `date`" >> $pipeline_log
		bs download project -i $project_id -o "$tmp_dir" --extension=json
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

	# set testing parameter to only run 2 batches with two samples in each batch
	if [[ "$testing_flag" == "Y" ]]; then
		
		for (( batch_id=1; batch_id<=$batch_count; batch_id++ )); do
			
			batch_manifest=$log_dir/batch_0$batch_id.txt
			
			if [[ "$batch_id" == 1 ]] || [[ "$batch_id" == 2 ]]; then
				head -2 $batch_manifest > tmp.txt
				mv tmp.txt $batch_manifest
			else
				rm $batch_manifest
			fi
		done
		
		#set the batch count
		batch_count=2

	fi
       
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

        	        #move files to batch fasta dir
                        mv $fastq_dir/${sample_id}*/*fastq.gz $fastq_batch_dir
                                
			if [[ "$qc_flag" == "Y" ]]; then
				
                        	#make sample tmp_dir: tmp_dir/sample_id
                        	if [[ ! -d "$tmp_dir/${sample_id}" ]]; then mkdir $tmp_dir/${sample_id}; fi

				#unzip analysis file downloaded from DRAGEN to sample tmp dir - used in QC
                		unzip -o -q $tmp_dir/${sample_id}_[0-9]*/*_all_output_files.zip -d $tmp_dir/${sample_id}

                		#move needed files to general tmp dir
				mv $tmp_dir/${sample_id}/ma/* $tmp_dir/unzipped
                        	
				#remove sample tmp dir, downloaded proj dir
                        	rm -r --force $tmp_dir/${sample_id}
				rm -r --force $tmp_dir/${sample_id}_[0-9]*/
			fi
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
                if [[ "$qc_flag" == "Y" ]]; then
			for f in $cecret_batch_dir/samtools_stats/aligned/*.stats.txt; do
                		frag_length=`cat $f | grep "average length" | awk '{print $4}'`
				file_name=`echo $f | rev | cut -f1 -d "/" | rev`
				file_name=${file_name%.stats*}
				echo -e "${file_name}\t${frag_length}\t${batch_id}" >> $merged_fragment
			done
		fi

		#mv all files to  master dirs
		if [[ "$qc_flag" == "Y" ]]; then
			mv $cecret_batch_dir/fastqc/* $fastqc_dir
			mv $cecret_batch_dir/ivar_variants/* $ivar_dir
		fi
		mv $cecret_batch_dir/consensus/* $gisaid_dir

		#remove intermediate files
		sudo rm -r --force work
		sudo rm -r --force $cecret_batch_dir
		sudo rm -r --force $fastq_batch_dir
	done

	#############################################################################################
	# Create reports
	#############################################################################################
	if [[ "$qc_flag" == "Y" ]]; then
		#log
		echo "--Creating QC Report"
		echo "--Creating QC Report" >> $pipeline_log
		echo "---Starting time: `date`" >> $pipeline_log
        	echo "---Starting space: `df . | sed -n '2 p' | awk '{print $5}'`" >> $pipeline_log

		#-d -dd 1 adds dir name to sample name
		multiqc -f -v \
        		-c $log_dir/multiqc_config.yaml \
        		$fastqc_dir \
        		$tmp_dir/unzipped \
        		-o $qcreport_dir
	
	
        	#create fragment plot
	        python scripts/fragment_plots.py $merged_fragment $fragement_plot

	fi
		
	#create final results file
	final_nextclade=$intermed_dir/final_nextclade.txt
	final_pangolin=$intermed_dir/final_pangolin.txt

	## remove duplicate headers
	#from pangolin: sampleid, pangolin status, lineage
	#from nextclade: sampleid, clade
	cat $merged_nextclade | sort | uniq -u | awk -F';' '{print $1,$2}'| \
		awk '{ gsub(/Consensus_/,"",$1) gsub(/\.consensus_[a-z0-9._]*/,"",$1); print }'| awk '{ print $1","$2"_"$3 }' | awk '{ gsub(/"/,"",$2); print }' > $final_nextclade
	cat $merged_pangolin | sort | uniq -u |  awk -F',' '{print $1,$12,$2}'| \
		awk '{ gsub(/Consensus_/,"",$1) gsub(/\.consensus_[a-z0-9._]*/,"",$1); print }' | awk '{print $1","$2","$3}' > $final_pangolin
	
	##pass to final results
        head -1 $merged_cecret > $final_results
	cat $merged_cecret | sort | uniq | awk -F"\t" '{ print $1","$25","$3","$20 }' | head -n -1 >> $final_results
	
	echo "---Ending time: `date`" >> $pipeline_log

	#remove all proj files
	#rm -r --force $tmp_dir
	rm -r --force $cecret_dir
	rm -r --force $fastq_dir
	rm -r --force $fastqc_dir

	echo "Ending time: `date`" >> $pipeline_log
	echo "Ending space: `df . | sed -n '2 p' | awk '{print $5}'`" >> $pipeline_log
	echo "*** PIPELINE COMPLETE ***" >> $pipeline_log

elif [[ "$pipeline" == "gisaid" ]]; then

        #############################################################################################
        # Run GISAID UPLOAD
        #############################################################################################
        echo "*** STARTING PIPELINE ***"
	echo "--GISAID Upload"

	# run check
	fasta_number=`ls "$fasta_dir"/*.fa | wc -l`
	if [[ "$fasta_number" -lt 1 ]]; then 
		echo "Missing fasta files"
       	else
		echo "Processing $fasta_number samples"
	fi
	
	# set args
	metadata_file=$(cat "${pipeline_config}" | grep "metadata_file: " | sed 's/metadata_file: //' | sed 's/"//g')
	metadata_loc=$log_dir/$metadata_file

	#run gisaid script
	bash scripts/gisaid.sh "${gisaid_dir}" "${project_id}" "${pipeline_config}" "$metadata_loc" 2> "${log_dir}/gisaid_warnings.txt"
	
else
	echo "Pipeline options (-p) must be init, run, gisaid or update"
fi

