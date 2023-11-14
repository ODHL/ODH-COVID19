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
# helper functions
#############################################################################################

helpFunction()
{
   echo ""
   echo "Usage: $1 -r [REQUIRED] runmode"
   echo -e "\t-r options: init, cecret, gisaid, ncbi, stat"
   echo "Usage: $2 -n [REQUIRED] project_id"
   echo -e "\t-n project id"
   echo "Usage: $3 -s [OPTIONAL] subworkflow options"
   echo -e "\t-s DOWNLOAD, BATCH, CECRET, ALL"   
   echo "Usage: $4 -r [OPTIONAL] resume options"
   echo -e "\t-r Y,N option to resume -p GISAID workflow in progress"
   exit 1 # Exit script after printing help
}

while getopts "m:n:t:r:" opt
do
   case "$opt" in
        m ) pipeline="$OPTARG" ;;
        n ) project_id="$OPTARG" ;;
        t ) testing_flag="$OPTARG" ;;
       	r ) reject_flag="$OPTARG" ;;
	? ) helpFunction ;; # Print helpFunction in case parameter is non-existent
   esac
done

# Print helpFunction in case parameters are empty
if [ -z "$pipeline" ] || [ -z "$project_id" ]; then
   echo "Some or all of the parameters are empty";
   helpFunction
fi

#############################################################################################
# other functions
#############################################################################################
check_initialization(){
  if [[ ! -d $log_dir ]] || [[ ! -f "$pipeline_config" ]]; then
    echo "ERROR: You must initalize the dir before beginning pipeline"
    exit 1
  fi
}

# source global functions
source $(dirname "$0")/scripts/functions.sh

#############################################################################################
# args
#############################################################################################
# Remove trailing / to project_name if it exists
# some projects may have additional information (IE OH-1234 SARS ONLY) in the name
# To avoid issues within project naming schema remove all information after spaces
# To ensure consistency in all projects, remove all information after _
project_name_full=$(echo $project_id | sed 's:/*$::')
project_name=$(echo $project_id | cut -f1 -d "_" | cut -f1 -d " ")

#set defaults for optional args
if [ -z "$testing_flag" ]; then testing_flag="N"; fi
if [ -z "$partial_flag" ]; then partial_flag="N"; fi
if [ -z "$reject_flag" ]; then reject_flag="N"; fi

# set date
date_stamp=`echo 20$project_name | sed 's/OH-[A-Z]*[0-9]*-//'`

#############################################################################################
# Dir, Configs
#############################################################################################
# set dirs
output_dir="/home/ubuntu/output/$project_name"
log_dir=$output_dir/logs
analysis_dir=$output_dir/analysis

# analysis dirs
fasta_dir=$analysis_dir/fasta
intermed_dir=$analysis_dir/intermed
final_results=$analysis_dir/final_results_$date_stamp.csv

# log dirs
qc_dir=$output_dir/qc
pipeline_log=$log_dir/pipeline_log.txt
multiqc_config="$log_dir/config_multiqc.yaml"
pipeline_config="$log_dir/config_pipeline.yaml"
cecret_config="$log_dir/config_cecret.config"

# tmp dir
tmp_dir=$output_dir/tmp

# ncbi dir to hold until completion of sampling
ncbi_hold="../ncbi_hold/$project_id"

#############################################################################################
# Run CECRET
#############################################################################################
if [[ "$pipeline" == "init" ]]; then
	
	# print message
	echo
	echo "*** INITIALIZING PIPELINE ***"

	#make directories, logs
    if [[ ! -d $output_dir ]]; then mkdir $output_dir; fi

    ##parent
	dir_list=(logs rawdata cecret tmp analysis)
    for pd in "${dir_list[@]}"; do if [[ ! -d $output_dir/$pd ]]; then mkdir -p $output_dir/$pd; fi; done

    ##tmp
    dir_list=(fastqc unzipped)
    for pd in "${dir_list[@]}"; do if [[ ! -d $tmp_dir/$pd ]]; then mkdir -p $tmp_dir/$pd; fi; done

    ##analysis
    dir_list=(fasta intermed qc reports)
    for pd in "${dir_list[@]}"; do if [[ ! -d $analysis_dir/$pd ]]; then mkdir -p $analysis_dir/$pd; fi; done

	dir_list=(not_uploaded gisaid_complete upload_failed)
	##fasta
    for pd in "${dir_list[@]}"; do if [[ ! -d $fasta_dir/$pd ]]; then mkdir -p $fasta_dir/$pd; fi; done

    ##log file
    touch $pipeline_log

	# copy config inputs to edit if doesn't exit
	files_save=("config/config_pipeline.yaml" "config/config_cecret.config" "config/config_multiqc.yaml")
  	for f in ${files_save[@]}; do
        IFS='/' read -r -a strarr <<< "$f"
    	if [[ ! -f "${log_dir}/${strarr[1]}" ]]; then
            cp $f "${log_dir}/${strarr[1]}"
		fi
	done

	#update metadata name
	sed -i "s~metadata.csv~${log_dir}/metadata-${project_name}.csv~" "${log_dir}/config_pipeline.yaml" 

  	#output
	echo -e "Configs are ready to be edited:\n${log_dir}"
	echo "*** INITIALIZATION COMPLETE ***"
	echo

elif [[ "$pipeline" == "update" ]]; then

    #update the staphb toolkit
    staphb-tk --auto_update

elif [[ "$pipeline" == "cecret" ]]; then
	
	#############################################################################################
    # Run CECRET pipeline
	#############################################################################################
   	message_cmd_log "------------------------------------------------------------------------"
    message_cmd_log "--- STARTING CECRET PIPELINE ---"

	# check initialization was completed
	check_initialization
	
    # Eval YAML args
	date_stamp=`echo 20$project_name | sed 's/OH-[A-Z]*[0-9]*-//'`

    # run pipelien
	bash scripts/cecret.sh \
		"${output_dir}" \
		"${project_name_full}" \
		"${pipeline_config}" \
		"${cecret_config}" \
		"${multiqc_config}" \
		"${date_stamp}" \
		"${pipeline_log}" \
		"${testing_flag}"
		
	# run QC
	bash scripts/seq_qc.sh \
		"${output_dir}" \
		"${pipeline_config}"

elif [[ "$pipeline" == "gisaid" ]]; then
	#########################################################
	# Eval, source
	#########################################################
	eval $(parse_yaml ${pipeline_config} "config_")

	############################################################################################
    # Run GISAID UPLOAD
    #############################################################################################
	if [[ $reject_flag == "N" ]]; then
		message_cmd_log "------------------------------------------------------------------------"
		message_cmd_log "--- STARTING GISAID PIPELINE ---"

        # Eval YAML args
    	metadata_file="$log_dir/$config_metadata_file"

   		#determine number of samples
		fasta_number=`ls "$fasta_dir/not_uploaded"/ | wc -l`
		
		# run QC on fasta samples
		if [[ "$fasta_number" -gt 0 ]]; then 
			echo "----Processing $fasta_number samples"
	        
			# check metadata file exists
        	if [[ ! -f $metadata_file ]]; then
        		echo "----Missing metadata file $metadata_file. File must be located in $log_dir. Review config_pipeline to update file name."
            	exit
        	fi
		else
			echo "----Missing fasta files"
			exit
		fi
		
		# log
		echo "--uploading samples" >> $pipeline_log
        	
		# run gisaid script
        bash scripts/gisaid.sh "${output_dir}" "${project_id}" "${pipeline_config}" "${final_results}" "${reject_flag}" 2>> "$pipeline_log"
        
	    # run stats
        # bash run_analysis_pipeline.sh -m stats -n $project_id
	else
		# determine number of samples
		sample_number=`cat reject_search.csv | wc -l`
        echo "--Processing rejected $sample_number samples"
	
		# find the samples that were rejected	
		if [[ -f reject_find.csv ]]; then rm reject_find.csv; fi
		while read search_id; do search_num=`echo $search_id | cut -f1 -d"," | cut -f4 -d"-" | cut -f1 -d"/" | \
		cut -f2 -d"C"`; file_name=`ls ../*/analysis/fasta/*/*$search_num.*`; echo "$search_id+$file_name"; done < reject_search.csv >> reject_find.csv
		
		file_number=`cat reject_find.csv | wc -l`

		# check one:to:one sample to file find
		if [[ $sample_number == $file_number ]]; then
			
			# for each rejected sample, run reject GISAID pipeline
			while read search_id; do
					
				# set new variables
				project_id=`echo $search_id | cut -f2 -d"+" | cut -f2 -d"/"` 
				date_stamp=`echo 20$project_id | sed 's/OH-[A-Z]*[0-9]*-//'`
				output_dir="../$project_id"
				pipeline_config="$output_dir/logs/config_pipeline.yaml"
				final_results="$output_dir/analysis/final_results_$date_stamp.csv"
				pipeline_log="$output_dir/logs/pipeline_log.txt"
				sample_id=`echo $search_id | cut -f1 -d","`

				# create rejected file
				reject_master="$output_dir/analysis/intermed/gisaid_rejected.csv"
				reject_tmp="$output_dir/analysis/intermed/gisaid_rejected_tmp.csv"
			
				echo $search_id | cut -f1 -d"+" > $reject_tmp
				
				if [[ -f $rejected_master ]]; then
					cat $reject_tmp >> $reject_master
				else
					cp $reject_tmp $reject_master
				fi
				
				echo "----$sample_id"

				# process sample
				bash scripts/gisaid.sh "${output_dir}" "${project_id}" "${pipeline_config}" "${final_results}" "${reject_flag}" 2>> "$pipeline_log"
			done < reject_find.csv

			#log 
	        echo "--analyzing rejected samples" >> $pipeline_log
			rm $reject_tmp
		else
			echo "Number of files does not match samples. Review log"
			exit
		fi

	fi

	message_cmd_log "--- GISAID PIPELINE COMPLETE ---"
	message_cmd_log "------------------------------------------------------------------------"
elif [[ "$pipeline" == "ncbi" ]]; then
	
    ##########################################################
    # Eval, source
    #########################################################
	eval $(parse_yaml ${pipeline_config} "config_")

	#############################################################################################
    # Run NCBI UPLOAD
    #############################################################################################
	message_cmd_log "------------------------------------------------------------------------"
	message_cmd_log "--- STARTING NCBI PIPELINE ---"

	# set args
	date_stamp=`echo 20$project_name | sed 's/OH-[A-Z]*[0-9]*-//'`
	ncbi_mput=$log_dir/${project_id}_${date_stamp}_mput.txt
	gisaid_results=$analysis_dir/intermed/gisaid_results.csv

    # Eval YAML args
	metadata_file="$log_dir/$config_metadata_file"

    # run inital upload or merge results
	if [[ $reject_flag == "N" ]]; then	
		# determine number of samples
		fasta_number=`ls "$fasta_dir/upload_partial"/ | wc -l`
		
		if [[ $fasta_number -gt 1 ]]; then
			# run batch command
			bash scripts/ncbi.sh "${output_dir}" "${project_id}" "${pipeline_config}" "${gisaid_results}" "${reject_flag}" "${final_results}"
			
		else
			echo "No samples for upload"
		fi
	else
		# merge multiple NCBI outputs
		header="header.txt"
		joined="joined.txt"
		cleaned="cleaned.txt"
		final="metadata-processed-ok.tsv"
		for f in $ncbi_hold/complete/metadata*ok*; do
			if [[ ! -f $header ]]; then head -n1 $f > $header; fi
    		if [[ ! -f $joined ]]; then touch $joined; fi
    		cat $f >> $joined
			
			# rename the file
			new_name=`echo $f | sed "s/-processed-ok//g"`
    		mv $f $new_name
		done

		cat $header > $ncbi_hold/complete/$final
		grep -v "accession" $joined > $cleaned
		cat $cleaned | sort | uniq >> $ncbi_hold/complete/$final
		rm $header $joined $cleaned

   		# check metadata return file is in dir
		ncbi_sra=`ls $ncbi_hold/complete/*ok*`
		
		# run batch command
		if [[ -f $ncbi_sra ]]; then
			bash scripts/ncbi.sh "${output_dir}" "${project_id}" "${pipeline_config}" "${gisaid_results}" "${reject_flag}" "${final_results}"
		
			# run stats
            bash run_analysis_pipeline.sh -m stats -n $project_id
		else
			echo "MISSING metadata output file"
		fi
	fi

	# complete
	message_cmd_log "--- COMPLETED NCBI PIPELINE ---"

elif [[ "$pipeline" == "stats" ]]; then
        
	# create stats file
	stats_log=$log_dir/stats.txt
	touch $stats_log

	################ General
	message_stats_log "*** RUNNING PIPELINE STATS ***"
	
	# total number
    val=`ls ${output_dir}/analysis/fasta/*/*.fa | wc -l`
	message_stats_log "--Total number of samples $val"
	
	# number failed pipeline QC
	val1=`cat $final_results | grep "qc_fail" | grep -v "missing_metadata" | grep -v "gisaid_rejected" | grep -v "gisaid_fail" |  wc -l`
	message_stats_log "----Number failed pipeline QC: $val1"

	# number of samples with missing metadata
    val2=`cat $final_results | grep "missing" | wc -l`
    message_stats_log "----Number missing metadata: $val2"
    if [[ $val2 -gt 0 ]]; then
    	cat $intermed_dir/gisaid_results.csv | grep "missing" > $log_dir/missing_metadata.csv
    	sed -i "s/gisaid_fail/$project_id/g" $log_dir/missing_metadata.csv
    fi
	
	val=$((val-val1-val2))
    message_stats_log "----Number pased pipeline QC: $val"

	################# GISAID
	message_stats_log "-- GISAID STATS"
	# number uploaded success
	val=`cat $final_results | grep "gisaid_pass" | wc -l`
	message_stats_log "---- Number GISAID uploaded successfully: $val"

	# number failed upload
    val=`cat $final_results | grep -e "gisaid_fail" -e "gisaid_rejected" | wc -l`
	message_stats_log "---- Number GISAID uploaded and rejected: $val"
	
	################## NCBI
	message_stats_log "-- NCBI Results"
    # number passed upload
    val=`cat $final_results | grep "ncbi_pass" | wc -l`
    message_stats_log "---- Number NCBI uploaded: $val"

    # number passed upload
    val=`cat $final_results | grep "ncbi_duplicated" | wc -l`
    message_stats_log "---- Number NCBI duplicated: $val"

	message_stats_log "*** COMPLETE PIPELINE ***"
elif [[ "$pipeline" == "cleanup" ]]; then
	project_id=$project_name
	project_date=$date_stamp
	
	cd ..
	if [[ $reject_flag == "Y" ]]; then
		for f in $project_id/analysis/intermed/*; do sed -i "s/-${project_id}//g" $f; done
		ncbi_results="$project_id/analysis/intermed/ncbi_results.csv"
		final_results="$project_id/analysis/final_results_$project_date.csv"
		final_cecret="$project_id/analysis/intermed/final_cecret.txt"
		final_nextclade="$project_id/analysis/intermed/final_nextclade.txt"
		sed -i "s/>Consensus_//g" $project_id/analysis/intermed/gisaid_results.csv
		sed -i "s/\.fa//g" $project_id/analysis/intermed/gisaid_results.csv
		sed -i "s/gisaid_fail,qc/qc_fail,qc/g" $project_id/analysis/intermed/gisaid_results.csv
		echo "sample_id,pango_qc,nextclade_clade,pangolin_lineage,pangolin_scorpio,aa_substitutions" > $final_results
		join <(sort $final_cecret) <(sort $final_nextclade) -t $',' >> $final_results
		sort $project_id/analysis/intermed/gisaid_results.csv > tmp_gresults.txt
		sort $project_id/analysis/final_results_$project_date.csv > tmp_fresults.txt
		echo "sample_id,gisaid_status,gisaid_notes,pango_qc,nextclade_clade,pangolin_lineage,pangolin_scorpio,aa_substitutions" > "$final_results"
		join <(sort tmp_gresults.txt) <(sort tmp_fresults.txt) -t $',' >> "$final_results"
		cat $ncbi_results | grep -v "fail" > tmp_nresults.txt
		cat $final_results | grep "fail" | awk -F"," '{print $1,$2,"NA"}'| sed -s "s/ /,/g" | sed -s "s/gisaid_fail/qc_fail/g" >> tmp_nresults.txt
		sort $final_results > tmp_fresults.txt
		echo "sample_id,ncbi_status,ncbi_notes,gisaid_status,gisaid_notes,pango_qc,nextclade_clade,pangolin_lineage,pangolin_scorpio,aa_substitutions" > $final_results
		join <(sort tmp_nresults.txt) <(sort tmp_fresults.txt) -t $',' >> $final_results
	fi

	# zip fasta folder
	if [[ ! -f $project_id/analysis/fasta.tar.gz ]]; then tar -zcvf $project_id/analysis/fasta.tar.gz $project_id/analysis/fasta; fi

	# remove ncbi_hold dir
	rm -r ncbi_hold/$project_id

	# return to dir
	cd analysis*
	bash run_analysis_pipeline.sh -m stats -n $project_id

else
	echo "Pipeline options (-p) must be init, cecret, gisaid, ncbi, stats, update or cleanup"
fi

