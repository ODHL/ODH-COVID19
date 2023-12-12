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
   echo "Usage: $1 -p [REQUIRED] pipeline runmode"
   echo -e "\t-p options: init, sarscov2, gisaid, ncbi, stat, update"
   echo "Usage: $2 -n [REQUIRED] project_id"
   echo -e "\t-n project id"
   echo "Usage: $3 -s [REQUIRED] subworkflow options"
   echo -e "\t-s DOWNLOAD, BATCH, ANALYZE REPORT CLEAN ALL | PREP UPLOAD QC"
   echo "Usage: $4 -r [OPTIONAL] resume options"
   echo -e "\t-r Y,N option to resume -p GISAID workflow in progress"
   echo "Usage: $5 -t [OPTIONAL] testing options"
   echo -e "\t-r Y,N option to run test"
   echo "Usage: $6 -e [OPTIONAL] working environment"
   echo -e "\t-r iop,aws option to specify analysis enivornment"
   exit 1 # Exit script after printing help
}

while getopts "p:n:s:r:t:e:" opt
do
   case "$opt" in
        p ) pipeline="$OPTARG" ;;
        n ) project_id="$OPTARG" ;;
        s ) subworkflow="$OPTARG" ;;
       	r ) resume="$OPTARG" ;;
       	t ) testing="$OPTARG" ;;		
       	e ) environment="$OPTARG" ;;		
	? ) helpFunction ;; # Print helpFunction in case parameter is non-existent
   esac
done

# Print helpFunction in case parameters are empty
if [ -z "$pipeline" ] || [ -z "$project_id" ]; then
   echo "Some or all of the parameters are empty";
   helpFunction
fi
if [ -z "$resume" ]; then resume="N";fi
if [ -z "$testing" ]; then testing="N";fi
if [ -z "$environment" ]; then environment="aws";fi
#############################################################################################
# other functions
#############################################################################################
check_initialization(){
  if [[ ! -d $log_dir ]] || [[ ! -f "$pipeline_config" ]]; then
    echo "ERROR: You must initalize the dir before beginning pipeline"
	echo "$log_dir"
	echo "$pipeline_config"
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

# set date
date_stamp=`echo 20$project_name | sed 's/OH-[A-Z]*[0-9]*-//'`

#############################################################################################
# Dir, Configs
#############################################################################################
# set dirs
output_dir="/home/ubuntu/output/$project_name"
log_dir=$output_dir/logs
analysis_dir=$output_dir/analysis
rawdata_dir=$output_dir/rawdata
tmp_dir=$output_dir/tmp
pipeline_dir=$output_dir/pipeline

# set files
final_results=$analysis_dir/reports/final_results_$date_stamp.csv
pipeline_log=$log_dir/pipeline_log.txt
multiqc_config="$log_dir/config/config_multiqc.yaml"
pipeline_config="$log_dir/config/config_pipeline.yaml"
cecret_config="$log_dir/config/config_cecret.config"

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

    ## parent
	dir_list=(logs rawdata pipeline tmp analysis)
    for pd in "${dir_list[@]}"; do if [[ ! -d $output_dir/$pd ]]; then mkdir -p $output_dir/$pd; fi; done

    ## tmp
    dir_list=(fastqc unzipped)
    for pd in "${dir_list[@]}"; do if [[ ! -d $tmp_dir/$pd ]]; then mkdir -p $tmp_dir/$pd; fi; done

	## logs
	dir_list=(config manifests pipeline gisaid ncbi)
    for pd in "${dir_list[@]}"; do if [[ ! -d $log_dir/$pd ]]; then mkdir -p $log_dir/$pd; fi; done

    ## analysis
    dir_list=(fasta intermed qc reports)
    for pd in "${dir_list[@]}"; do if [[ ! -d $analysis_dir/$pd ]]; then mkdir -p $analysis_dir/$pd; fi; done
	
	#### fasta
	dir_list=(not_uploaded gisaid_complete upload_failed)
    for pd in "${dir_list[@]}"; do if [[ ! -d $analysis_dir/fasta/$pd ]]; then mkdir -p $analysis_dir/fasta/$pd; fi; done

    ##log file
    touch $pipeline_log

	# copy config inputs to edit if doesn't exit
	files_save=("config/config_pipeline.yaml" "config/config_cecret.config" "config/config_multiqc.yaml")
  	for f in ${files_save[@]}; do
        IFS='/' read -r -a strarr <<< "$f"
    	if [[ ! -f "${log_dir}/config/${strarr[1]}" ]]; then
            cp $f "${log_dir}/config/${strarr[1]}"
		fi
	done

	#update metadata name
	sed -i "s~metadata.csv~${log_dir}/manifests/metadata-${project_name}.csv~" "${log_dir}/config/config_pipeline.yaml" 

	# copy report scripts
	cp scripts/COVID* $analysis_dir/reports

  	#output
	echo -e "Configs are ready to be edited:\n${log_dir}/config"
	echo "*** INITIALIZATION COMPLETE ***"
	echo

elif [[ "$pipeline" == "update" ]]; then

    #update the staphb toolkit
    staphb-tk --auto_update

elif [[ "$pipeline" == "validate_iop" ]]; then
	# init
	bash run_analysis_pipeline.sh -n OH-VH00648-231124 -p init -e aws
	bash run_analysis_pipeline.sh -n OH-VH00648-231124 -p sarscov2 -s lala -e aws

elif [[ "$pipeline" == "validate" ]]; then
	# remove prev runs
	sudo rm -rf ~/output/OH-VH00648-231124

	# init
	bash run_analysis_pipeline.sh -n OH-VH00648-231124 -p init

	# run through workflow
    bash run_analysis_pipeline.sh -n OH-VH00648-231124 -p sarscov2 -s DOWNLOAD
    bash run_analysis_pipeline.sh -n OH-VH00648-231124 -p sarscov2 -s BATCH -t Y
	# cp -r ~/output/OH-VH00648-231124/savelogs ~/output/OH-VH00648-231124/logs
	# cp  -r ~/output/OH-VH00648-231124/savetmp ~/output/OH-VH00648-231124/tmp
    bash run_analysis_pipeline.sh -n OH-VH00648-231124 -p sarscov2 -s ANALYZE -t Y -r N
    bash run_analysis_pipeline.sh -n OH-VH00648-231124 -p sarscov2 -s REPORT -t Y
    # bash run_analysis_pipeline.sh -n OH-VH00648-231124 -p sarscov2 -s lala -t Y
elif [[ "$pipeline" == "sarscov2" ]]; then
	
	#############################################################################################
    # Run CECRET pipeline
	#############################################################################################
   	message_cmd_log "------------------------------------------------------------------------"
    message_cmd_log "--- STARTING SARS-COV2 PIPELINE ---"

	# check initialization was completed
	check_initialization

    # run SARS-COV2 pipeline
	bash scripts/analysis.sh \
		"${output_dir}" \
		"${project_name_full}" \
		"${pipeline_config}" \
		"${cecret_config}" \
		"${multiqc_config}" \
		"${date_stamp}" \
		"${pipeline_log}" \
		"${subworkflow}" \
		"${resume}" \
		"${testing}"

elif [[ "$pipeline" == "gisaid" ]]; then
	#########################################################
	# Eval, source
	#########################################################
	eval $(parse_yaml ${pipeline_config} "config_")

	############################################################################################
    # Run GISAID UPLOAD
    #############################################################################################
	message_cmd_log "------------------------------------------------------------------------"
	message_cmd_log "--- STARTING GISAID PIPELINE ---"

   	# determine number of samples
	fasta_number=`ls "$analysis_dir/fasta/not_uploaded"/ | wc -l`
		
	# run QC on fasta samples
	if [[ "$fasta_number" -gt 0 ]]; then 
		echo "----Processing $fasta_number samples"
	        
		# check metadata file exists
        if [[ ! -f $config_metadata_file ]]; then
        	echo "----Missing metadata file $config_metadata_file. File must be located in $log_dir. Review config_pipeline to update file name."
        	exit
    	fi
	else
		echo "----Missing fasta files"
		exit
	fi
		
	# log
	echo "--uploading samples" >> $pipeline_log
        	
	# run gisaid script
    bash scripts/gisaid.sh \
		"${output_dir}" \
		"${project_id}" \
		"${pipeline_config}" \
		"${final_results}" \
		"${subworkflow}" 2>> "$pipeline_log"
        
	# run stats
    bash run_analysis_pipeline.sh -m stats -n $project_id

	# log
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
		fasta_number=`ls "$analysis_dir/fasta/upload_partial"/ | wc -l`
		
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
else
	echo "Pipeline options (-p) must be init, sarscov2, gisaid, ncbi, stats, update"
fi